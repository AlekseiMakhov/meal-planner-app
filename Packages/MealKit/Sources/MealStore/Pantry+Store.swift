import Foundation
import GRDB
import MealCore

/// A line typed into the pantry or the shopping list, read the way ingredient lines are: «яйца 10», «молоко 1 л».
public struct TypedLine: Hashable, Sendable {
    public var name: String
    public var amount: Double?
    public var unit: MeasureUnit?
    /// The product the name means, if the base has it.
    public var match: ProductMatch

    public init(name: String, amount: Double? = nil, unit: MeasureUnit? = nil, match: ProductMatch) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.match = match
    }
}

extension AppDatabase {
    /// What a typed line names, one entry per product: «соль, перец» gives two.
    public func readLines(_ text: String) throws -> [TypedLine] {
        try IngredientParser.parse(text).map { part in
            TypedLine(
                name: part.name, amount: part.amount, unit: part.amount == nil ? nil : part.unit,
                match: try matchProduct(named: part.name))
        }
    }

    // MARK: - Reading the pantry

    public func pantry(_ query: PantryQuery, limit: Int, offset: Int = 0) throws -> ListPage<PantryEntry> {
        try reader.read { db in try PantryListSQL.page(db, query, limit: limit, offset: offset) }
    }

    public func observePantry(_ query: PantryQuery, limit: Int) -> AsyncValueObservation<ListPage<PantryEntry>> {
        ValueObservation.trackingConstantRegion { db in try PantryListSQL.page(db, query, limit: limit) }
            .removeDuplicates().values(in: reader)
    }

    public func pantryItem(productID: Product.ID) throws -> PantryItem? {
        try reader.read { db in try PantryItemRecord.fetchOne(db, key: productID)?.item }
    }

    /// What there is of these products: the recipe page compares its lines with it.
    public func pantryItems(for productIDs: some Collection<Product.ID>) throws -> [Product.ID: PantryItem] {
        try reader.read { db in try Self.fetchPantryItems(db, Set(productIDs)) }
    }

    public func observePantryItems(for productIDs: Set<Product.ID>) -> AsyncValueObservation<[Product.ID: PantryItem]> {
        ValueObservation.trackingConstantRegion { db in try Self.fetchPantryItems(db, productIDs) }
            .removeDuplicates().values(in: reader)
    }

    static func fetchPantryItems(_ db: Database, _ productIDs: Set<Product.ID>) throws -> [Product.ID: PantryItem] {
        guard !productIDs.isEmpty else { return [:] }
        return try PantryItemRecord.fetchAll(db, keys: productIDs)
            .reduce(into: [:]) { result, record in result[record.productId] = record.item }
    }

    // MARK: - Changing the pantry

    /// Sets what there is of the product: `quantity` in its base unit, nil for some, uncounted; zero — it ran
    /// out. `isLow` nil keeps the mark as it was.
    @discardableResult
    public func setPantry(_ productID: Product.ID, quantity: Double?, isLow: Bool? = nil) throws -> PantryItem {
        if let quantity, quantity < 0 {
            throw StoreError("Количество не бывает отрицательным.")
        }
        return try writer.write { db in
            guard try ProductRecord.exists(db, key: productID) else { throw StoreError("Продукта больше нет.") }
            let old = try PantryItemRecord.fetchOne(db, key: productID)
            let item = PantryItem(
                productID: productID, quantity: quantity, isLow: isLow ?? old?.isLow ?? false, updatedAt: .now)
            try PantryItemRecord(item).upsert(db)
            try RecipeDerived.refresh(db, recipeIDs: RecipeDerived.recipes(using: productID, db))
            return item
        }
    }

    /// Adds what was bought or found: amounts in the products' base units; nil only marks the product as there.
    /// A product bought is no longer running low.
    public func addToPantry(_ amounts: [Product.ID: Double?]) throws {
        try writer.write { db in try Self.addToPantry(amounts, db) }
    }

    static func addToPantry(_ amounts: [Product.ID: Double?], _ db: Database) throws {
        for (productID, amount) in amounts {
            guard try ProductRecord.exists(db, key: productID) else { continue }
            var item = try PantryItemRecord.fetchOne(db, key: productID)?.item ?? PantryItem(productID: productID)
            if let amount, amount > 0 {
                item.quantity = (item.quantity ?? 0) + amount
            } else if !item.isInStock {
                item.quantity = nil
            }
            item.isLow = false
            item.updatedAt = .now
            try PantryItemRecord(item).upsert(db)
        }
        try RecipeDerived.refresh(db, recipeIDs: RecipeDerived.recipes(using: Array(amounts.keys), db))
    }

    /// Takes amounts out of the pantry: what a dish used. What is not counted stays as it is; nothing goes below
    /// zero.
    public func takeFromPantry(_ amounts: [Product.ID: Double]) throws {
        try writer.write { db in try Self.takeFromPantry(amounts, db) }
    }

    static func takeFromPantry(_ amounts: [Product.ID: Double], _ db: Database) throws {
        for (productID, amount) in amounts {
            guard var item = try PantryItemRecord.fetchOne(db, key: productID)?.item, let quantity = item.quantity
            else { continue }
            item.quantity = max(quantity - amount, 0)
            item.updatedAt = .now
            try PantryItemRecord(item).upsert(db)
        }
        try RecipeDerived.refresh(db, recipeIDs: RecipeDerived.recipes(using: Array(amounts.keys), db))
    }

    /// Marks the product as running low, or not.
    public func setLow(_ isLow: Bool, productID: Product.ID) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE pantry_item SET isLow = ?, updatedAt = ? WHERE productId = ?",
                arguments: [isLow, Date.now, productID])
        }
    }

    /// Stops keeping track of the products at home.
    public func removeFromPantry(_ productIDs: Set<Product.ID>) throws {
        try writer.write { db in
            _ = try PantryItemRecord.deleteAll(db, keys: productIDs)
            try RecipeDerived.refresh(db, recipeIDs: RecipeDerived.recipes(using: productIDs, db))
        }
    }
}
