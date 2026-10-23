import MealCore
import Testing

@testable import MealStore

/// The starting base, as Tools/seed/build.py wrote it.
struct SeedCatalogTests {
    private let seed = try! SeedCatalog.decoded()

    /// Calories against the macronutrients: with USDA's own factors for the food when it has them (cocoa's
    /// carbohydrate gives 1.33 kcal a gram), else 4, 9 and 4 kcal per gram; alcohol adds 7. Vinegars are
    /// left out: their energy is acetic acid, which none of the four counts.
    @Test func caloriesAgreeWithMacronutrients() {
        for product in seed.products where product.energy == nil {
            let factors = product.factors ?? [4, 9, 4]
            let expected =
                factors[0] * product.protein + factors[1] * product.fat + factors[2] * product.carbs
                + 7 * (product.alcohol ?? 0)
            let tolerance = product.factors == nil ? max(0.15 * product.kcal, 10) : max(0.08 * product.kcal, 5)
            #expect(
                abs(product.kcal - expected) <= tolerance,
                "\(product.name): \(product.kcal) kcal, macros give \(expected)")
        }
    }

    @Test func theExceptionsAreTheVinegars() {
        #expect(
            Set(seed.products.filter { $0.energy != nil }.map(\.key)) == [
                "vinegar", "apple-vinegar", "balsamic", "wine-vinegar",
            ])
    }

    @Test func everyProductCanBeSavedAndFound() {
        var names: [String: String] = [:]
        let aisles = Set(seed.aisles.map(\.key))
        for item in seed.products {
            let product = Product(
                id: 0, name: item.name, aliases: item.aliases, kcal: item.kcal, protein: item.protein, fat: item.fat,
                carbs: item.carbs, gramsPerPiece: item.gramsPerPiece, density: item.density)
            #expect(product.problems.isEmpty, "\(item.name): \(product.problems)")
            #expect(aisles.contains(item.aisle), "\(item.name): \(item.aisle)")
            for name in [item.name] + item.aliases {
                let key = SearchText.normalized(name)
                #expect(names[key, default: item.key] == item.key, "«\(name)» belongs to \(names[key] ?? "")")
                names[key] = item.key
            }
        }
    }

    @Test func unitsAreUsable() {
        for item in seed.products {
            #expect(BaseUnit(rawValue: item.baseUnit) != nil, "\(item.name)")
            #expect(NutritionSource(rawValue: item.source) != nil, "\(item.name)")
            if item.baseUnit == "ml" {
                #expect(item.density != nil, "\(item.name) is measured in millilitres without a density")
            }
            if item.baseUnit == "pcs" {
                #expect(item.gramsPerPiece != nil, "\(item.name) is counted without a piece weight")
            }
            for unit in (item.units ?? [:]).keys {
                #expect(MeasureUnit(rawValue: unit)?.kind == .named, "\(item.name): \(unit)")
            }
        }
    }

    @Test func usdaProductsNameTheirEntry() {
        for item in seed.products where item.source == "usda" {
            #expect(item.sourceNote.hasPrefix("USDA FDC "), "\(item.name)")
        }
        #expect(seed.products.count >= 300)
    }

    @Test func seededDatabaseHasEveryProductInItsAisle() throws {
        let database = try AppDatabase.inMemory(seeded: true)
        let aisles = try database.aisles()
        #expect(aisles.map(\.name) == seed.aisles.map(\.name))
        let page = try database.products(ProductQuery(), limit: 1000)
        #expect(page.total == seed.products.count)
        #expect(page.rows.allSatisfy { $0.aisleID != nil && $0.nutrition != nil && $0.seedKey != nil })
        let egg = try #require(try database.product(named: "яиц"))
        #expect(egg.name == "Яйцо куриное")
        #expect(egg.baseUnit == .piece)
        #expect(egg.units.grams(2, .piece) == 100)
        #expect(egg.sourceNote == "USDA FDC 171287 · Egg, whole, raw, fresh")
    }
}
