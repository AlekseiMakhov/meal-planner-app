"""Builds the starting product base from Tools/seed/catalog.py and USDA FoodData Central SR Legacy.

    python3 -I Tools/seed/build.py <folder of FoodData_Central_sr_legacy_food_csv_2018-04>

The USDA folder comes from https://fdc.nal.usda.gov/download-datasets (SR Legacy, CSV, April 2018).
Writes Packages/MealKit/Sources/MealStore/Seed/SeedCatalog+Data.swift: the seed as JSON in a Swift
string, because the MCP tool embedded in the app cannot reach a SwiftPM resource bundle.
"""

import csv
import json
import runpy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "Packages/MealKit/Sources/MealStore/Seed/SeedCatalog+Data.swift"
SEED_VERSION = 1

# USDA nutrient ids.
NUTRIENTS = {"1008": "kcal", "1003": "protein", "1004": "fat", "1005": "carbs", "1079": "fiber", "1018": "alcohol"}
# US household measures in millilitres.
MEASURES = [("cup", 236.588), ("fl oz", 29.5735), ("tbsp", 14.7868), ("tsp", 4.92892)]


def load_usda(folder, wanted):
    foods = {}
    with open(folder / "food.csv", encoding="utf-8") as file:
        for row in csv.DictReader(file):
            fdc = int(row["fdc_id"])
            if fdc in wanted:
                foods[fdc] = {"description": row["description"], "portions": []}
    with open(folder / "food_nutrient.csv", encoding="utf-8") as file:
        for row in csv.DictReader(file):
            key = NUTRIENTS.get(row["nutrient_id"])
            fdc = int(row["fdc_id"])
            if key and fdc in foods:
                foods[fdc][key] = float(row["amount"])
    with open(folder / "food_portion.csv", encoding="utf-8") as file:
        for row in csv.DictReader(file):
            fdc = int(row["fdc_id"])
            if fdc in foods:
                foods[fdc]["portions"].append(
                    (float(row["amount"] or 0), row["modifier"].strip().lower(), float(row["gram_weight"] or 0)))
    # The Atwater factors USDA computed each food's calories with: cocoa's carbohydrate gives 1.33 kcal a gram.
    with open(folder / "food_calorie_conversion_factor.csv", encoding="utf-8") as file:
        factors = {row["food_nutrient_conversion_factor_id"]: tuple(
            float(row[key]) for key in ("protein_value", "fat_value", "carbohydrate_value"))
            for row in csv.DictReader(file) if row["protein_value"] and row["fat_value"] and row["carbohydrate_value"]}
    with open(folder / "food_nutrient_conversion_factor.csv", encoding="utf-8") as file:
        for row in csv.DictReader(file):
            fdc = int(row["fdc_id"])
            if fdc in foods and row["id"] in factors:
                foods[fdc]["factors"] = factors[row["id"]]
    missing = wanted - foods.keys()
    if missing:
        sys.exit(f"not in SR Legacy: {sorted(missing)}")
    return foods


def density(portions):
    """Grams per millilitre from the plainest household measure USDA gives, or None."""
    candidates = []
    for amount, modifier, grams in portions:
        for rank, (measure, millilitres) in enumerate(MEASURES):
            if amount > 0 and grams > 0 and modifier.startswith(measure):
                plain = modifier == measure
                candidates.append((0 if plain else 1, rank, grams / (amount * millilitres)))
    return round(min(candidates)[2], 3) if candidates else None


def energy_gap(entry):
    """Calories minus what the macronutrients give, with the food's own factors or else 4, 9 and 4 kcal per
    gram, and 7 per gram of alcohol. Mirrors SeedCatalogTests."""
    protein, fat, carbs = entry.get("factors", (4, 9, 4))
    expected = (protein * entry["protein"] + fat * entry["fat"] + carbs * entry["carbs"]
                + 7 * (entry.get("alcohol") or 0))
    return entry["kcal"] - expected


def energy_tolerance(entry):
    # Published factors reproduce USDA's own calories within a few per cent (Alaska pollock is off by 6 %);
    # general factors are only a sanity check.
    return max(0.08 * entry["kcal"], 5) if "factors" in entry else max(0.15 * entry["kcal"], 10)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    catalog = runpy.run_path(str(Path(__file__).with_name("catalog.py")))
    aisles = [{"key": key, "name": name} for key, name in catalog["AISLES"]]
    aisle_keys = {aisle["key"] for aisle in aisles}
    items = catalog["CATALOG"]
    usda = load_usda(Path(sys.argv[1]), {item["source"]["fdc"] for item in items if item["source"]["kind"] == "usda"})

    products, names, problems = [], {}, []
    for item in items:
        source = item["source"]
        entry = {"key": item["key"], "name": item["name"], "aliases": item["aliases"], "aisle": item["aisle"]}
        if item["aisle"] not in aisle_keys:
            problems.append(f"{item['key']}: unknown aisle {item['aisle']}")
        if source["kind"] == "usda":
            food = usda[source["fdc"]]
            for key in ("kcal", "protein", "fat", "carbs"):
                entry[key] = round(food.get(key, 0.0), 2)
            if food.get("alcohol"):
                entry["alcohol"] = round(food["alcohol"], 2)
            if "factors" in food:
                entry["factors"] = list(food["factors"])
            entry["source"] = "usda"
            entry["sourceNote"] = f"USDA FDC {source['fdc']} · {food['description']}"
            if source.get("energy"):
                entry["energy"] = source["energy"]
            derived = density(food["portions"])
        else:
            kcal, protein, fat, carbs = source["values"]
            entry.update(kcal=kcal, protein=protein, fat=fat, carbs=carbs, source=source["kind"])
            entry["sourceNote"] = ("Типичные значения с упаковки" if source["kind"] == "label"
                                   else "Справочные значения")
            derived = None
        entry["baseUnit"] = item["base"]
        if item["piece"]:
            entry["gramsPerPiece"] = item["piece"]
        chosen = item["density"] or derived
        if chosen:
            entry["density"] = chosen
        if item["base"] == "ml" and not chosen:
            problems.append(f"{item['key']}: measured in ml but has no density")
        if item["base"] == "pcs" and not item["piece"]:
            problems.append(f"{item['key']}: counted in pieces but has no piece weight")
        if item["units"]:
            entry["units"] = item["units"]
        if item["staple"]:
            entry["staple"] = True
        gap = energy_gap(entry)
        if not entry.get("energy") and abs(gap) > energy_tolerance(entry):
            problems.append(f"{item['key']}: {entry['kcal']} kcal, but macros give {entry['kcal'] - gap:.1f}")
        for name in [item["name"]] + item["aliases"]:
            key = name.lower().replace("ё", "е")
            if key in names and names[key] != item["key"]:
                problems.append(f"{item['key']}: «{name}» is also {names[key]}")
            names[key] = item["key"]
        products.append(entry)

    if problems:
        sys.exit("\n".join(problems))
    if len({p["key"] for p in products}) != len(products):
        sys.exit("duplicate keys")

    lines = [json.dumps(entry, ensure_ascii=False, separators=(", ", ": ")) for entry in products]
    seed = (
        "{\n"
        f"\"version\": {SEED_VERSION},\n"
        "\"aisles\": [\n" + ",\n".join(json.dumps(a, ensure_ascii=False) for a in aisles) + "\n],\n"
        "\"products\": [\n" + ",\n".join(lines) + "\n]\n"
        "}"
    )
    json.loads(seed)  # stays valid JSON
    # Indented the way swift-format lays out the literal, so `make format` leaves the file alone; Swift strips
    # the indentation of the closing delimiter from every line.
    indented = "\n".join("        " + line for line in seed.split("\n"))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        "// Generated by Tools/seed/build.py from Tools/seed/catalog.py and USDA FoodData Central SR Legacy.\n"
        "// Do not edit by hand: change the catalog and run `make seed`.\n\n"
        "extension SeedCatalog {\n"
        "    static let json = #\"\"\"\n" + indented + "\n        \"\"\"#\n"
        "}\n",
        encoding="utf-8")
    print(f"{len(products)} products in {len(aisles)} aisles → {OUTPUT.relative_to(ROOT)}")


main()
