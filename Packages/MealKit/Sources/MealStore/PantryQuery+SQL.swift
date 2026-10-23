import GRDB
import MealCore

/// The pantry list in SQL. The search matches the beginnings of the words of the product's name and aliases,
/// as the full-text index does: the pantry is a few hundred rows at most, so it does without one.
enum PantryListSQL {
    /// The pantry item has some: a counted amount above zero, or some uncounted.
    static let inStock = "(pantry_item.quantity IS NULL OR pantry_item.quantity > \(PantryItem.tolerance))"

    static func page(_ db: Database, _ query: PantryQuery, limit: Int, offset: Int = 0) throws -> ListPage<PantryEntry>
    {
        let rows = try SQLRequest<Row>(
            literal: """
                SELECT product.*, pantry_item.quantity AS pantryQuantity, pantry_item.isLow AS pantryLow,
                pantry_item.updatedAt AS pantryUpdatedAt
                """ + " " + source(query) + " ORDER BY " + order(query) + " LIMIT \(limit) OFFSET \(offset)"
        ).fetchAll(db)
        let entries = try rows.map { row in
            let product = try ProductRecord(row: row).product
            return PantryEntry(
                product: product,
                item: PantryItem(
                    productID: product.id, quantity: row["pantryQuantity"], isLow: row["pantryLow"],
                    updatedAt: row["pantryUpdatedAt"]))
        }
        let total = try SQLRequest<Int>(literal: "SELECT COUNT(*) " + source(query)).fetchOne(db) ?? 0
        return ListPage(rows: entries, total: total)
    }

    /// Each word of the search has to begin a word of the text.
    static func matches(_ text: String, column: String) -> [SQL] {
        SearchText.terms(text).map { term in
            SQL(sql: "(' ' || \(column)) LIKE ?", arguments: ["% " + term + "%"])
        }
    }

    private static func source(_ query: PantryQuery) -> SQL {
        var sql: SQL = """
            FROM pantry_item JOIN product ON product.id = pantry_item.productId
            LEFT JOIN aisle ON aisle.id = product.aisleId
            """
        var conditions = matches(query.text, column: "product.searchText")
        if !query.aisleIDs.isEmpty {
            conditions.append("product.aisleId IN \(query.aisleIDs.sorted())")
        }
        if let days = query.menuDays {
            conditions.append(
                """
                product.id IN (SELECT recipe_ingredient.productId FROM plan_entry
                JOIN recipe_ingredient ON recipe_ingredient.recipeId = plan_entry.recipeId
                WHERE plan_entry.day BETWEEN \(days.lowerBound.description) AND \(days.upperBound.description)
                AND plan_entry.cookedAt IS NULL)
                """)
        }
        if !query.statuses.isEmpty {
            let statuses: [SQL] = query.statuses.sorted { $0.rawValue < $1.rawValue }.map { status in
                switch status {
                case .inStock: SQL(sql: inStock + " AND NOT pantry_item.isLow")
                case .low: SQL(sql: inStock + " AND pantry_item.isLow")
                case .out: SQL(sql: "NOT " + inStock)
                }
            }
            conditions.append(statuses.map { "(" + $0 + ")" }.joined(separator: " OR "))
        }
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.map { "(" + $0 + ")" }.joined(separator: " AND ")
        }
        return sql
    }

    private static func order(_ query: PantryQuery) -> SQL {
        var terms: [String] = []
        for term in query.sort {
            let direction = term.direction == .ascending ? "ASC" : "DESC"
            switch term.key {
            case .aisle: terms += ["aisle.position IS NULL", "aisle.position \(direction)"]
            case .name: terms.append("product.nameKey \(direction)")
            case .quantity: terms += ["pantry_item.quantity IS NULL", "pantry_item.quantity \(direction)"]
            case .updatedAt: terms.append("pantry_item.updatedAt \(direction)")
            }
        }
        terms += ["product.nameKey ASC", "product.id ASC"]
        return SQL(sql: terms.joined(separator: ", "))
    }
}

/// The shopping list in SQL: bought items always last, then the order asked for.
enum ShoppingListSQL {
    static func page(
        _ db: Database, _ query: ShoppingQuery, limit: Int, offset: Int = 0
    ) throws -> ListPage<ShoppingEntry> {
        let records = try SQLRequest<ShoppingItemRecord>(
            literal: "SELECT shopping_item.* " + source(query) + " ORDER BY " + order(query)
                + " LIMIT \(limit) OFFSET \(offset)"
        ).fetchAll(db)
        let products = try ProductRecord.fetchAll(db, keys: Set(records.compactMap(\.productId)))
            .reduce(into: [Int64: Product]()) { result, record in result[record.id ?? 0] = record.product }
        let entries = records.map { record in
            ShoppingEntry(item: record.item, product: record.productId.flatMap { products[$0] })
        }
        let total = try SQLRequest<Int>(literal: "SELECT COUNT(*) " + source(query)).fetchOne(db) ?? 0
        return ListPage(rows: entries, total: total)
    }

    private static func source(_ query: ShoppingQuery) -> SQL {
        var sql: SQL = """
            FROM shopping_item LEFT JOIN product ON product.id = shopping_item.productId
            LEFT JOIN aisle ON aisle.id = product.aisleId
            """
        var conditions = PantryListSQL.matches(
            query.text, column: "COALESCE(product.searchText, shopping_item.textKey, '')")
        if !query.aisleIDs.isEmpty {
            conditions.append("product.aisleId IN \(query.aisleIDs.sorted())")
        }
        if let isChecked = query.isChecked {
            conditions.append("(shopping_item.checkedAt IS NOT NULL) = \(isChecked)")
        }
        if let recipeID = query.recipeID {
            conditions.append(
                "EXISTS (SELECT 1 FROM json_each(shopping_item.reasons) WHERE json_extract(value, '$.recipeID') = \(recipeID))"
            )
        }
        if let day = query.day {
            conditions.append(
                "EXISTS (SELECT 1 FROM json_each(shopping_item.reasons) WHERE json_extract(value, '$.day') = \(day))")
        }
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.map { "(" + $0 + ")" }.joined(separator: " AND ")
        }
        return sql
    }

    private static let nameKey = "COALESCE(product.nameKey, shopping_item.textKey, '')"

    private static func order(_ query: ShoppingQuery) -> SQL {
        var terms = ["shopping_item.checkedAt IS NOT NULL"]
        for term in query.sort {
            let direction = term.direction == .ascending ? "ASC" : "DESC"
            switch term.key {
            case .aisle: terms += ["aisle.position IS NULL", "aisle.position \(direction)"]
            case .name: terms.append("\(nameKey) \(direction)")
            case .createdAt: terms.append("shopping_item.createdAt \(direction)")
            case .manual: terms.append("shopping_item.position \(direction)")
            }
        }
        terms += ["\(nameKey) ASC", "shopping_item.id ASC"]
        return SQL(sql: terms.joined(separator: ", "))
    }
}
