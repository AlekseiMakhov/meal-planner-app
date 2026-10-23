import Foundation
import GRDB
import MealCore

extension AppDatabase {
    // MARK: - Reading the shopping list

    public func shopping(_ query: ShoppingQuery, limit: Int, offset: Int = 0) throws -> ListPage<ShoppingEntry> {
        try reader.read { db in try ShoppingListSQL.page(db, query, limit: limit, offset: offset) }
    }

    public func observeShopping(_ query: ShoppingQuery, limit: Int) -> AsyncValueObservation<ListPage<ShoppingEntry>> {
        ValueObservation.trackingConstantRegion { db in try ShoppingListSQL.page(db, query, limit: limit) }
            .removeDuplicates().values(in: reader)
    }

    /// How many items are still to buy: the sidebar's badge.
    public func observeShoppingCount() -> AsyncValueObservation<Int> {
        ValueObservation.trackingConstantRegion { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM shopping_item WHERE checkedAt IS NULL") ?? 0
        }
        .removeDuplicates().values(in: reader)
    }

    public func shoppingEntries(ids: some Collection<ShoppingItem.ID>) throws -> [ShoppingEntry] {
        try reader.read { db in
            let records = try ShoppingItemRecord.fetchAll(db, keys: Set(ids)).sorted { ($0.id ?? 0) < ($1.id ?? 0) }
            let products = try ProductRecord.fetchAll(db, keys: Set(records.compactMap(\.productId)))
                .reduce(into: [Int64: Product]()) { result, record in result[record.id ?? 0] = record.product }
            return records.map { ShoppingEntry(item: $0.item, product: $0.productId.flatMap { products[$0] }) }
        }
    }

    // MARK: - Changing the shopping list

    /// Puts additions on the list. An item not yet bought for the same product, or with the same text, grows
    /// instead of a second one appearing; amounts that do not add up make a line of their own. Returns the items
    /// added to or made: none when everything was there already for the same reasons.
    @discardableResult
    public func addToShopping(_ additions: [ShoppingAddition]) throws -> [ShoppingItem.ID] {
        try writer.write { db in try Self.addToShopping(additions, db) }
    }

    static func addToShopping(_ additions: [ShoppingAddition], _ db: Database) throws -> [ShoppingItem.ID] {
        var ids: [ShoppingItem.ID] = []
        for addition in additions {
            var units: UnitProfile?
            var candidates: [ShoppingItemRecord]
            var text: String?
            if let productID = addition.productID {
                guard let product = try ProductRecord.fetchOne(db, key: productID)?.product else {
                    throw StoreError("Продукта больше нет.")
                }
                units = product.units
                candidates = try ShoppingItemRecord.filter(
                    Column("productId") == productID && Column("checkedAt") == nil
                )
                .order(Column("id")).fetchAll(db)
            } else {
                text = addition.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let text, !text.isEmpty else { throw StoreError("Нужно, что купить.") }
                candidates = try ShoppingItemRecord.filter(
                    Column("productId") == nil && Column("textKey") == SearchText.normalized(text)
                        && Column("checkedAt") == nil
                ).order(Column("id")).fetchAll(db)
            }
            if let amount = addition.amount, amount < 0 {
                throw StoreError("Количество не бывает отрицательным.")
            }
            if let (record, grown) = candidates.lazy.compactMap({ record in
                record.item.adding(addition, units: units).map { (record, $0) }
            }).first {
                if grown != record.item {
                    try ShoppingItemRecord(grown, id: record.id).update(db)
                    ids.append(record.id ?? 0)
                }
                continue
            }
            let position = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM shopping_item") ?? 0
            var record = ShoppingItemRecord(
                ShoppingItem(
                    id: 0, productID: addition.productID, text: text, amount: addition.amount, unit: addition.unit,
                    reasons: addition.reason.map { [$0] } ?? [], position: position),
                id: nil)
            try record.insert(db)
            ids.append(record.id ?? 0)
        }
        return ids
    }

    /// What the recipe, made for `servings`, is short of at home, put on the list with the recipe as the reason.
    @discardableResult
    public func addShortages(ofRecipe recipeID: Recipe.ID, servings: Int? = nil) throws -> [ShoppingItem.ID] {
        try writer.write { db in
            guard let details = try RecipeDerived.details(db, id: recipeID) else {
                throw StoreError("Рецепта больше нет.")
            }
            let pantry = try Self.fetchPantryItems(db, Set(details.ingredients.map(\.productID)))
            return try Self.addToShopping(details.shortages(servings: servings, pantry: pantry), db)
        }
    }

    /// Changes how much to buy, or the text of an item that is no product.
    public func updateShoppingItem(_ id: ShoppingItem.ID, amount: Double?, unit: MeasureUnit?, text: String? = nil)
        throws
    {
        if let amount, amount < 0 {
            throw StoreError("Количество не бывает отрицательным.")
        }
        try writer.write { db in
            guard var item = try ShoppingItemRecord.fetchOne(db, key: id)?.item else {
                throw StoreError("Этой покупки больше нет.")
            }
            item.amount = amount
            item.unit = amount == nil ? nil : unit
            if item.productID == nil, let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                item.text = text
            }
            try ShoppingItemRecord(item, id: id).update(db)
        }
    }

    public func removeShoppingItems(_ ids: Set<ShoppingItem.ID>) throws {
        try writer.write { db in _ = try ShoppingItemRecord.deleteAll(db, keys: ids) }
    }

    /// Marks items bought, or not bought after all.
    public func setChecked(_ checked: Bool, items ids: Set<ShoppingItem.ID>) throws {
        try writer.write { db in
            try db.execute(
                literal: "UPDATE shopping_item SET checkedAt = \(checked ? Date.now : nil) WHERE id IN \(Array(ids))")
        }
    }

    /// Puts what was bought into the pantry: `amounts` in the products' base units, nil — there is some,
    /// uncounted. The items leave the list, or with `keepOnList` stay there, bought and put away.
    public func stockBought(_ amounts: [ShoppingItem.ID: Double?], keepOnList: Bool = false) throws {
        try writer.write { db in
            var pantry: [Product.ID: Double?] = [:]
            for (id, amount) in amounts {
                guard var record = try ShoppingItemRecord.fetchOne(db, key: id), record.stockedAt == nil else {
                    continue
                }
                if let productID = record.productId {
                    let sum = (pantry[productID] ?? nil).map { $0 + (amount ?? 0) } ?? amount
                    pantry[productID] = sum
                }
                if keepOnList {
                    record.checkedAt = record.checkedAt ?? .now
                    record.stockedAt = .now
                    try record.update(db)
                } else {
                    try record.delete(db)
                }
            }
            try Self.addToPantry(pantry, db)
        }
    }

    /// Takes the bought items off the list; returns how many there were.
    @discardableResult
    public func clearChecked() throws -> Int {
        try writer.write { db in try ShoppingItemRecord.filter(Column("checkedAt") != nil).deleteAll(db) }
    }

    /// The manual order: `ids` first, in this order, the rest after them as they were.
    public func reorderShopping(_ ids: [ShoppingItem.ID]) throws {
        try writer.write { db in
            let rest = try Int64.fetchAll(db, sql: "SELECT id FROM shopping_item ORDER BY position, id")
                .filter { !ids.contains($0) }
            for (position, id) in (ids + rest).enumerated() {
                try db.execute(sql: "UPDATE shopping_item SET position = ? WHERE id = ?", arguments: [position, id])
            }
        }
    }
}
