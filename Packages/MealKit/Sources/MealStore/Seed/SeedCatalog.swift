import Foundation
import GRDB
import MealCore

/// The starting product base: aisles and about 350 products with nutrition from USDA FoodData Central or
/// typical package values. Tools/seed/build.py writes it into SeedCatalog+Data.swift.
public enum SeedCatalog {
    public struct Seed: Decodable, Sendable {
        public let version: Int
        public let aisles: [SeedAisle]
        public let products: [SeedProduct]
    }

    public struct SeedAisle: Decodable, Sendable {
        public let key: String
        public let name: String
    }

    public struct SeedProduct: Decodable, Sendable {
        public let key: String
        public let name: String
        public let aliases: [String]
        public let aisle: String
        public let kcal: Double
        public let protein: Double
        public let fat: Double
        public let carbs: Double
        /// Grams of alcohol, which gives energy outside the macronutrients.
        public let alcohol: Double?
        /// USDA's Atwater factors for protein, fat and carbohydrate, when it used food-specific ones.
        public let factors: [Double]?
        /// Why the calories cannot be checked against the macronutrients, such as acetic acid in vinegar.
        public let energy: String?
        public let source: String
        public let sourceNote: String
        public let baseUnit: String
        public let gramsPerPiece: Double?
        public let density: Double?
        public let units: [String: Double]?
        public let staple: Bool?
    }

    public static func decoded() throws -> Seed {
        try JSONDecoder().decode(Seed.self, from: Data(json.utf8))
    }

    static func insert(into db: Database) throws {
        let seed = try decoded()
        let now = Date.now
        var aisles: [String: Int64] = [:]
        for (position, aisle) in seed.aisles.enumerated() {
            var record = AisleRecord(name: aisle.name, position: position, seedKey: aisle.key)
            try record.insert(db)
            aisles[aisle.key] = record.id
        }
        for item in seed.products {
            let product = Product(
                id: 0, name: item.name, aliases: item.aliases, aisleID: aisles[item.aisle], kcal: item.kcal,
                protein: item.protein, fat: item.fat, carbs: item.carbs,
                baseUnit: BaseUnit(rawValue: item.baseUnit) ?? .gram, gramsPerPiece: item.gramsPerPiece,
                density: item.density,
                namedUnits: Dictionary(
                    uniqueKeysWithValues: (item.units ?? [:]).compactMap { key, grams in
                        MeasureUnit(rawValue: key).map { ($0, grams) }
                    }),
                isStaple: item.staple ?? false, nutritionSource: NutritionSource(rawValue: item.source),
                sourceNote: item.sourceNote, seedKey: item.key, createdAt: now, updatedAt: now)
            var record = ProductRecord(product, id: nil)
            try record.insert(db)
        }
    }
}
