import Foundation
import GRDB
import MealCore

/// What a product name means in the base.
public enum ProductMatch: Hashable, Sendable {
    case found(Product)
    /// Several products fit; the closest first.
    case ambiguous([Product])
    case none
}

extension AppDatabase {
    // MARK: - Aisles

    public func aisles() throws -> [Aisle] {
        try reader.read { db in try Self.fetchAisles(db) }
    }

    public func observeAisles() -> AsyncValueObservation<[Aisle]> {
        ValueObservation.trackingConstantRegion { db in try Self.fetchAisles(db) }.removeDuplicates().values(in: reader)
    }

    private static func fetchAisles(_ db: Database) throws -> [Aisle] {
        try AisleRecord.order(Column("position"), Column("id")).fetchAll(db).map(\.aisle)
    }

    // MARK: - Reading products

    public func product(id: Int64) throws -> Product? {
        try reader.read { db in try ProductRecord.fetchOne(db, key: id)?.product }
    }

    public func observeProduct(id: Int64) -> AsyncValueObservation<Product?> {
        ValueObservation.trackingConstantRegion { db in try ProductRecord.fetchOne(db, key: id)?.product }
            .removeDuplicates().values(in: reader)
    }

    /// The product called so, by its name or one of its aliases, ignoring case and «ё».
    public func product(named name: String) throws -> Product? {
        let key = SearchText.normalized(name)
        guard !key.isEmpty else { return nil }
        return try reader.read { db in
            if let record = try ProductRecord.filter(Column("nameKey") == key).fetchOne(db) {
                return record.product
            }
            let candidates = try ProductListSQL.page(
                db, ProductQuery(text: name, sort: [SortTerm(.relevance)]), limit: 50)
            return candidates.rows.first { $0.aliases.contains { SearchText.normalized($0) == key } }
        }
    }

    /// `limit` products of the query from `offset` on, and how many there are in all.
    public func products(_ query: ProductQuery, limit: Int, offset: Int = 0) throws -> ListPage<Product> {
        try reader.read { db in try ProductListSQL.page(db, query, limit: limit, offset: offset) }
    }

    /// The product a name means. A name or alias that matches exactly wins; otherwise any form of the words
    /// is looked for, and a single result is taken. Several results are a question for whoever asked.
    public func matchProduct(named name: String) throws -> ProductMatch {
        if let product = try product(named: name) {
            return .found(product)
        }
        let candidates = try products(ProductQuery(text: name, sort: [SortTerm(.relevance)]), limit: 20).rows
        switch candidates.count {
        case 0: return .none
        case 1: return .found(candidates[0])
        default:
            // «сахара» means «Сахар», not «Сахар коричневый»: a name or alias of the very same words wins.
            let terms = SearchText.terms(name)
            let whole = candidates.filter { product in
                ([product.name] + product.aliases).contains { SearchText.terms($0) == terms }
            }
            return whole.count == 1 ? .found(whole[0]) : .ambiguous(Array(candidates.prefix(6)))
        }
    }

    public func aisle(named name: String) throws -> Aisle? {
        let key = SearchText.normalized(name)
        return try aisles().first { SearchText.normalized($0.name) == key }
    }

    /// The same, kept current as products change.
    public func observeProducts(_ query: ProductQuery, limit: Int) -> AsyncValueObservation<ListPage<Product>> {
        ValueObservation.trackingConstantRegion { db in try ProductListSQL.page(db, query, limit: limit) }
            .removeDuplicates().values(in: reader)
    }

    // MARK: - Changing products

    /// A new empty product: «Новый продукт», or «Новый продукт 2» when that is taken.
    public func newProduct(named name: String = "Новый продукт", aisleID: Int64? = nil) throws -> Product {
        try writer.write { db in
            var candidate = name
            var number = 1
            while try ProductRecord.filter(Column("nameKey") == SearchText.normalized(candidate)).fetchCount(db) > 0 {
                number += 1
                candidate = "\(name) \(number)"
            }
            var record = ProductRecord(Product(id: 0, name: candidate, aisleID: aisleID), id: nil)
            try record.insert(db)
            return record.product
        }
    }

    /// Saves the product's changes, tidied: refuses a missing or taken name and values out of range.
    @discardableResult
    public func save(_ product: Product) throws -> Product {
        let product = product.tidied()
        if let problem = product.problems.first {
            throw StoreError(problem.description)
        }
        return try writer.write { db in
            guard var record = try ProductRecord.fetchOne(db, key: product.id) else {
                throw StoreError("Продукта больше нет.")
            }
            let taken = try ProductRecord.filter(Column("nameKey") == product.nameKey && Column("id") != product.id)
                .fetchOne(db)
            if let taken {
                throw StoreError("Продукт «\(taken.name)» уже есть.")
            }
            var changed = product
            changed.createdAt = record.createdAt
            changed.updatedAt = .now
            let old = record.product
            record = ProductRecord(changed, id: product.id)
            try record.update(db)
            if old.baseUnit != changed.baseUnit {
                try Self.convertPantry(of: product.id, from: old.baseUnit, to: changed, db)
            }
            // Its recipes' nutrition and search text follow the product.
            try RecipeDerived.refresh(db, recipeIDs: RecipeDerived.recipes(using: product.id, db))
            return record.product
        }
    }

    /// What there is at home follows the product's new base unit; an amount that does not convert becomes
    /// uncounted rather than wrong.
    private static func convertPantry(of productID: Product.ID, from old: BaseUnit, to product: Product, _ db: Database)
        throws
    {
        guard var item = try PantryItemRecord.fetchOne(db, key: productID)?.item, let quantity = item.quantity,
            item.isInStock
        else { return }
        item.quantity = product.units.convert(quantity, from: old.unit, to: product.baseUnit.unit)
        try PantryItemRecord(item).update(db)
    }

    /// How many recipes use the product, the trashed ones included.
    public func recipeCount(of productID: Product.ID) throws -> Int {
        try reader.read { db in try RecipeDerived.recipes(using: productID, db).count }
    }

    /// Refuses a product that recipes use: it has to be taken out of them, or merged into another one.
    public func deleteProduct(id: Int64) throws {
        try writer.write { db in
            let recipes = try RecipeDerived.recipes(using: id, db).count
            if recipes > 0 {
                let name = try ProductRecord.fetchOne(db, key: id)?.name ?? "Продукт"
                let count = RussianPlural.form(for: Double(recipes), one: "рецепте", few: "рецептах", many: "рецептах")
                throw StoreError(
                    "«\(name)» есть в \(recipes) \(count). Уберите его оттуда или объедините с другим продуктом.")
            }
            _ = try ProductRecord.deleteOne(db, key: id)
        }
    }

    /// Folds a duplicate into the product that stays: the duplicate's name and aliases become aliases, and
    /// what the one that stays lacks — nutrition, piece weight, density, units, aisle — comes from the
    /// duplicate. Recipes, the pantry and the shopping list that had the duplicate have the kept product.
    @discardableResult
    public func mergeProduct(_ duplicateID: Int64, into keptID: Int64) throws -> Product {
        guard duplicateID != keptID else { throw StoreError("Продукт нельзя объединить с самим собой.") }
        return try writer.write { db in
            guard let duplicate = try ProductRecord.fetchOne(db, key: duplicateID)?.product,
                var kept = try ProductRecord.fetchOne(db, key: keptID)?.product
            else { throw StoreError("Одного из продуктов больше нет.") }

            kept.aliases += [duplicate.name] + duplicate.aliases
            if kept.nutrition == nil, duplicate.nutrition != nil {
                kept.nutrition = duplicate.nutrition
                kept.nutritionSource = duplicate.nutritionSource
                kept.sourceNote = duplicate.sourceNote
                kept.needsReview = kept.needsReview || duplicate.needsReview
            }
            kept.gramsPerPiece = kept.gramsPerPiece ?? duplicate.gramsPerPiece
            kept.density = kept.density ?? duplicate.density
            kept.namedUnits.merge(duplicate.namedUnits) { own, _ in own }
            kept.aisleID = kept.aisleID ?? duplicate.aisleID
            kept.isStaple = kept.isStaple || duplicate.isStaple
            kept.updatedAt = .now
            kept = kept.tidied()

            try db.execute(
                sql: "UPDATE recipe_ingredient SET productId = ? WHERE productId = ?", arguments: [keptID, duplicateID])
            try db.execute(
                sql: "UPDATE shopping_item SET productId = ? WHERE productId = ?", arguments: [keptID, duplicateID])
            try Self.mergePantry(of: duplicate, into: kept, db)
            try ProductRecord.deleteOne(db, key: duplicateID)
            let record = ProductRecord(kept, id: keptID)
            try record.update(db)
            try RecipeDerived.refresh(db, recipeIDs: RecipeDerived.recipes(using: keptID, db))
            return record.product
        }
    }

    /// The duplicate's pantry joins the kept product's: counted amounts add up in the kept product's unit, one
    /// that does not convert makes the stock uncounted.
    private static func mergePantry(of duplicate: Product, into kept: Product, _ db: Database) throws {
        guard let moved = try PantryItemRecord.fetchOne(db, key: duplicate.id)?.item else { return }
        let converted = moved.quantity.flatMap {
            kept.units.convert($0, from: duplicate.baseUnit.unit, to: kept.baseUnit.unit)
        }
        var item: PantryItem
        if let existing = try PantryItemRecord.fetchOne(db, key: kept.id)?.item {
            item = existing
            if let quantity = existing.quantity, moved.isInStock {
                item.quantity = converted.map { quantity + $0 }
            }
            item.isLow = existing.isLow && moved.isLow
        } else {
            item = PantryItem(productID: kept.id, quantity: moved.isInStock ? converted : 0, isLow: moved.isLow)
        }
        item.updatedAt = .now
        try PantryItemRecord(item).upsert(db)
        _ = try PantryItemRecord.deleteOne(db, key: duplicate.id)
    }
}
