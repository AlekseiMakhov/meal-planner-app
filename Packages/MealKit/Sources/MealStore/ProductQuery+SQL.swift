import GRDB
import MealCore

/// The product list in SQL: the search joins the full-text index, filters become conditions, and the order
/// ends with the name and the id so equal values keep their places from one block to the next.
enum ProductListSQL {
    static func page(_ db: Database, _ query: ProductQuery, limit: Int, offset: Int = 0) throws -> ListPage<Product> {
        let rows = try SQLRequest<ProductRecord>(
            literal: "SELECT product.* " + source(query) + " ORDER BY " + order(query)
                + " LIMIT \(limit) OFFSET \(offset)"
        ).fetchAll(db)
        let total = try SQLRequest<Int>(literal: "SELECT COUNT(*) " + source(query)).fetchOne(db) ?? 0
        return ListPage(rows: rows.map(\.product), total: total)
    }

    /// The prefixes of the query's stems, all of which must match: «сливочного масла» finds «Масло
    /// сливочное».
    static func matchPattern(_ text: String) -> String? {
        let terms = SearchText.terms(text)
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    private static func source(_ query: ProductQuery) -> SQL {
        var sql: SQL = "FROM product"
        if let pattern = matchPattern(query.text) {
            // CROSS JOIN keeps the full-text search as the outer loop: SQLite would otherwise run it again
            // for every product an aisle index hands it.
            sql = """
                FROM (SELECT rowid AS matchId, rank AS matchRank FROM product_ft WHERE product_ft MATCH \(pattern))
                AS found CROSS JOIN product ON product.id = found.matchId
                """
        }
        if query.sort.contains(where: { $0.key == .aisle }) {
            sql += " LEFT JOIN aisle ON aisle.id = product.aisleId"
        }
        var conditions: [SQL] = []
        if !query.aisleIDs.isEmpty {
            conditions.append("product.aisleId IN \(query.aisleIDs.sorted())")
        }
        if let isStaple = query.isStaple {
            conditions.append("product.isStaple = \(isStaple)")
        }
        let complete: SQL =
            "product.kcal IS NOT NULL AND product.protein IS NOT NULL AND product.fat IS NOT NULL AND product.carbs IS NOT NULL"
        switch query.nutrition {
        case .missing: conditions.append("NOT (" + complete + ")")
        case .needsReview: conditions.append("product.needsReview")
        case .complete: conditions.append(complete)
        case nil: break
        }
        if let kcalMin = query.kcal.min {
            conditions.append("product.kcal >= \(kcalMin)")
        }
        if let kcalMax = query.kcal.max {
            conditions.append("product.kcal <= \(kcalMax)")
        }
        if let isUsed = query.isUsedInRecipes {
            conditions.append(
                "EXISTS (SELECT 1 FROM recipe_ingredient WHERE recipe_ingredient.productId = product.id) = \(isUsed)")
        }
        if !query.sources.isEmpty {
            conditions.append("product.nutritionSource IN \(query.sources.map(\.rawValue).sorted())")
        }
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.map { "(" + $0 + ")" }.joined(separator: " AND ")
        }
        return sql
    }

    /// Built from the keys alone, never from what the person typed. Empty values go last either way.
    private static func order(_ query: ProductQuery) -> SQL {
        var terms: [String] = []
        let searching = matchPattern(query.text) != nil
        for term in query.sort {
            let direction = term.direction == .ascending ? "ASC" : "DESC"
            switch term.key {
            case .name: terms.append("product.nameKey \(direction)")
            case .aisle: terms += ["aisle.position IS NULL", "aisle.position \(direction)"]
            case .kcal, .protein, .fat, .carbs:
                let column = "product.\(term.key.rawValue)"
                terms += ["\(column) IS NULL", "\(column) \(direction)"]
            case .createdAt: terms.append("product.createdAt \(direction)")
            case .recipeCount:
                terms.append(
                    "(SELECT COUNT(DISTINCT recipeId) FROM recipe_ingredient WHERE productId = product.id) \(direction)"
                )
            case .relevance where searching: terms.append("found.matchRank \(direction)")
            case .relevance: break
            }
        }
        terms += ["product.nameKey ASC", "product.id ASC"]
        return SQL(sql: terms.joined(separator: ", "))
    }
}
