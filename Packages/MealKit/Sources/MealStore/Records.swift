import Foundation
import GRDB
import MealCore

struct AisleRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "aisle"

    var id: Int64?
    var name: String
    var position: Int
    var seedKey: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var aisle: Aisle {
        Aisle(id: id ?? 0, name: name, position: position)
    }
}

/// A product row. The name key and the search text are written from the name and aliases on every save,
/// so the uniqueness check and the search index never fall behind.
struct ProductRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "product"

    var id: Int64?
    var name: String
    var nameKey: String
    var aliases: [String]
    var aisleId: Int64?
    var kcal: Double?
    var protein: Double?
    var fat: Double?
    var carbs: Double?
    var baseUnit: String
    var gramsPerPiece: Double?
    var density: Double?
    var namedUnits: [String: Double]
    var isStaple: Bool
    var nutritionSource: String?
    var sourceNote: String?
    var needsReview: Bool
    var seedKey: String?
    var searchText: String
    var createdAt: Date
    var updatedAt: Date

    /// The row for a product; `id` nil inserts it as a new one.
    init(_ product: Product, id: Int64?) {
        self.id = id
        name = product.name
        nameKey = product.nameKey
        aliases = product.aliases
        aisleId = product.aisleID
        kcal = product.kcal
        protein = product.protein
        fat = product.fat
        carbs = product.carbs
        baseUnit = product.baseUnit.rawValue
        gramsPerPiece = product.gramsPerPiece
        density = product.density
        namedUnits = Dictionary(uniqueKeysWithValues: product.namedUnits.map { ($0.key.rawValue, $0.value) })
        isStaple = product.isStaple
        nutritionSource = product.nutritionSource?.rawValue
        sourceNote = product.sourceNote
        needsReview = product.needsReview
        seedKey = product.seedKey
        searchText = product.searchText
        createdAt = product.createdAt
        updatedAt = product.updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Values the app does not know, such as a unit from a later version, are left out rather than failing.
    var product: Product {
        Product(
            id: id ?? 0, name: name, aliases: aliases, aisleID: aisleId, kcal: kcal, protein: protein, fat: fat,
            carbs: carbs, baseUnit: BaseUnit(rawValue: baseUnit) ?? .gram, gramsPerPiece: gramsPerPiece,
            density: density,
            namedUnits: Dictionary(
                uniqueKeysWithValues: namedUnits.compactMap { key, grams in
                    MeasureUnit(rawValue: key).map { ($0, grams) }
                }),
            isStaple: isStaple, nutritionSource: nutritionSource.flatMap(NutritionSource.init(rawValue:)),
            sourceNote: sourceNote, needsReview: needsReview, seedKey: seedKey, createdAt: createdAt,
            updatedAt: updatedAt)
    }
}

struct PantryItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pantry_item"

    var productId: Int64
    var quantity: Double?
    var isLow: Bool
    var updatedAt: Date

    init(_ item: PantryItem) {
        productId = item.productID
        quantity = item.quantity
        isLow = item.isLow
        updatedAt = item.updatedAt
    }

    var item: PantryItem {
        PantryItem(productID: productId, quantity: quantity, isLow: isLow, updatedAt: updatedAt)
    }
}

/// A shopping list row. The reasons are kept as JSON, which the filter by recipe reads with `json_each`.
struct ShoppingItemRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "shopping_item"

    var id: Int64?
    var productId: Int64?
    var text: String?
    var textKey: String?
    var amount: Double?
    var unit: String?
    var reasons: [ShoppingReason]
    var checkedAt: Date?
    var stockedAt: Date?
    var position: Int
    var createdAt: Date

    init(_ item: ShoppingItem, id: Int64?) {
        self.id = id
        productId = item.productID
        text = item.text
        textKey = item.text.map(SearchText.normalized)
        amount = item.amount
        unit = item.unit?.rawValue
        reasons = item.reasons
        checkedAt = item.checkedAt
        stockedAt = item.stockedAt
        position = item.position
        createdAt = item.createdAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var item: ShoppingItem {
        ShoppingItem(
            id: id ?? 0, productID: productId, text: text, amount: amount,
            unit: unit.flatMap(MeasureUnit.init(rawValue:)),
            reasons: reasons, checkedAt: checkedAt, stockedAt: stockedAt, position: position, createdAt: createdAt)
    }
}
