import Foundation
import MCP
import MealCore
import MealStore

/// A mistake in a call, told to Claude in words it can act on.
struct ToolError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// How tool results are written: JSON with snake_case keys, numbers rounded to what is meaningful.
enum ToolOutput {
    /// Pretty-printed JSON for the text content of a result.
    static func json(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    static func number(_ value: Double?, places: Int = 1) -> Value {
        guard let value, value.isFinite else { return .null }
        let scale = pow(10, Double(places))
        let rounded = (value * scale).rounded() / scale
        return rounded.rounded() == rounded && abs(rounded) < 1e12 ? .int(Int(rounded)) : .double(rounded)
    }

    static func text(_ value: String?) -> Value {
        value.map(Value.string) ?? .null
    }

    /// An amount in a sentence: «545», «1.5».
    static func text(amount: Double) -> String {
        let rounded = (amount * 100).rounded() / 100
        return rounded == rounded.rounded() && abs(rounded) < 1e12 ? String(Int(rounded)) : String(rounded)
    }

    static func id(_ value: Int64) -> Value {
        .int(Int(value))
    }

    static func time(_ date: Date) -> Value {
        .string(date.formatted(Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: .current)))
    }

    static func nutrition(_ nutrition: Nutrition?) -> Value {
        guard let nutrition else { return .null }
        return .object([
            "kcal": number(nutrition.kcal, places: 0), "protein": number(nutrition.protein),
            "fat": number(nutrition.fat), "carbs": number(nutrition.carbs),
        ])
    }

    static func product(_ product: Product, aisles: [Int64: String]) -> Value {
        .object([
            "id": id(product.id),
            "name": .string(product.name),
            "aliases": .array(product.aliases.map(Value.string)),
            "aisle": text(product.aisleID.flatMap { aisles[$0] }),
            "kcal": number(product.kcal), "protein": number(product.protein, places: 2),
            "fat": number(product.fat, places: 2), "carbs": number(product.carbs, places: 2),
            "base_unit": .string(product.baseUnit.rawValue),
            "grams_per_piece": number(product.gramsPerPiece, places: 2),
            "density": number(product.density, places: 3),
            "units": .object(
                Dictionary(
                    uniqueKeysWithValues: product.namedUnits.map { ($0.key.rawValue, number($0.value, places: 2)) })),
            "staple": .bool(product.isStaple),
            "source": text(product.nutritionSource?.rawValue),
            "source_note": text(product.sourceNote),
            "needs_review": .bool(product.needsReview),
        ])
    }

    static func recipeCard(_ card: RecipeCard, categories: [Int64: String]) -> Value {
        .object([
            "id": id(card.id),
            "title": .string(card.title),
            "categories": .array(card.categoryIDs.compactMap { categories[$0] }.map(Value.string)),
            "kcal_per_100g": number(card.kcalPer100, places: 0),
            "per_serving": nutrition(card.perServing),
            "nutrition_complete": .bool(card.isNutritionComplete),
            "total_minutes": card.totalMinutes.map(Value.int) ?? .null,
            "servings": .int(card.servings),
            "favorite": .bool(card.isFavorite),
            "has_photo": .bool(card.photo != nil),
            "has_video": .bool(card.hasVideo),
            "missing_count": .int(card.missingCount),
        ])
    }

    static func status(_ status: PantryStatus) -> String {
        switch status {
        case .inStock: "in_stock"
        case .low: "low"
        case .out: "out"
        }
    }

    static func pantry(_ entry: PantryEntry, aisles: [Int64: String]) -> Value {
        .object([
            "product_id": id(entry.product.id),
            "product": .string(entry.product.name),
            "aisle": text(entry.product.aisleID.flatMap { aisles[$0] }),
            "quantity": number(entry.item.quantity, places: 2),
            "unit": .string(entry.product.baseUnit.rawValue),
            "status": .string(status(entry.item.status)),
            "low": .bool(entry.item.isLow),
            "minimum": number(entry.item.minimum, places: 2),
            "staple": .bool(entry.product.isStaple),
            "updated_at": time(entry.item.updatedAt),
        ])
    }

    static func shopping(_ entry: ShoppingEntry, aisles: [Int64: String]) -> Value {
        .object([
            "id": id(entry.item.id),
            "name": .string(entry.name),
            "product_id": entry.item.productID.map(id) ?? .null,
            "aisle": text(entry.product?.aisleID.flatMap { aisles[$0] }),
            "amount": number(entry.item.amount, places: 2),
            "unit": text(entry.item.amount == nil ? nil : (entry.item.unit ?? .piece).rawValue),
            "for": .array(
                entry.item.reasons.map { reason in
                    .object([
                        "title": .string(reason.title), "recipe_id": reason.recipeID.map(id) ?? .null,
                        "day": text(reason.day),
                    ])
                }),
            "checked": .bool(entry.item.isChecked),
            "in_pantry": .bool(entry.item.stockedAt != nil),
        ])
    }

    /// A whole recipe, its lines for `servings` when asked: amounts scale, nutrition per serving does not. With the
    /// pantry, each line says whether there is enough at home.
    static func recipe(
        _ details: RecipeDetails, servings: Int?, categories: [Int64: String], mealTypes: [Int64: String],
        pantry: [Product.ID: PantryItem]? = nil
    ) -> Value {
        let recipe = details.recipe
        let nutrition = details.nutrition
        let shown = servings ?? recipe.servings
        var missing: [Value] = []
        let lines: [Value] = details.ingredients.map { line in
            let product = details.products[line.productID]
            let scaled = line.scaled(to: shown, of: recipe.servings)
            if line.isMeasured, let product {
                if product.nutrition == nil {
                    missing.append(.string("нет КБЖУ у «\(product.name)»"))
                } else if line.grams(of: product) == nil {
                    missing.append(.string("«\(product.name)»: не пересчитать в граммы"))
                }
            }
            var atHome: Value = .null
            var needMore: Value = .null
            if let pantry, let product {
                let availability = scaled.availability(of: product, at: pantry[product.id])
                switch availability {
                case .enough: atHome = "enough"
                case .low(let missing):
                    atHome = "low"
                    needMore = number(missing, places: 2)
                case .missing(let needed):
                    atHome = "missing"
                    needMore = number(needed, places: 2)
                case .unknown: atHome = "unknown"
                }
            }
            return .object([
                "product_id": id(line.productID),
                "product": text(product?.name),
                "at_home": atHome,
                "need_more": needMore,
                "pantry_unit": text(product?.baseUnit.rawValue),
                "amount": number(scaled.amount, places: 2),
                "amount_max": number(scaled.amountMax, places: 2),
                "unit": text(scaled.effectiveUnit?.rawValue),
                "unit_title": text(scaled.effectiveUnit.map { $0.title(for: scaled.amountMax ?? scaled.amount ?? 1) }),
                "grams": number(product.flatMap { scaled.grams(of: $0) }, places: 0),
                "note": text(line.note),
                "group": text(line.group),
                "optional": .bool(line.isOptional),
            ])
        }
        return .object([
            "id": id(recipe.id),
            "title": .string(recipe.title),
            "servings": .int(recipe.servings),
            "ingredients_for_servings": .int(shown),
            "categories": .array(details.categoryIDs.compactMap { categories[$0] }.map(Value.string)),
            "meal_types": .array(details.mealTypeIDs.compactMap { mealTypes[$0] }.sorted().map(Value.string)),
            "prep_minutes": recipe.prepMinutes.map(Value.int) ?? .null,
            "cook_minutes": recipe.cookMinutes.map(Value.int) ?? .null,
            "yield_grams": number(recipe.yieldGrams, places: 0),
            "source_url": text(recipe.sourceURL),
            "video_url": text(recipe.videoURL),
            "video_player": text(recipe.videoURL.flatMap(VideoEmbed.player).map(\.provider.rawValue)),
            "has_photo": .bool(recipe.photo != nil),
            "notes": .string(recipe.notes),
            "favorite": .bool(recipe.isFavorite),
            "in_trash": .bool(recipe.deletedAt != nil),
            "ingredients": .array(lines),
            "missing_count": pantry.map { .int(details.availability(servings: shown, pantry: $0).missingCount) }
                ?? .null,
            "steps": .array(details.steps.map { .string($0.text) }),
            "nutrition": .object([
                "per_100g": self.nutrition(nutrition.per100g),
                "per_serving": self.nutrition(nutrition.perServing),
                "from_source": .bool(nutrition.isFromSource),
                "complete": .bool(nutrition.isComplete),
                "counted_ingredients": .int(nutrition.total.counted),
                "measured_ingredients": .int(nutrition.total.ingredients),
                "missing": .array(missing),
            ]),
            "created_at": time(recipe.createdAt),
            "updated_at": time(recipe.updatedAt),
        ])
    }
}
