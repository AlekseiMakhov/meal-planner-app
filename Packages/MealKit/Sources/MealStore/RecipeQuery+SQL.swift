import GRDB
import MealCore

/// The recipe lists in SQL. The nutrition table has a row per recipe; the gallery has a row per recipe and
/// category, ordered by the categories first, so its blocks fill the groups in turn.
enum RecipeListSQL {
    static func cards(_ db: Database, _ query: RecipeQuery, limit: Int) throws -> ListPage<RecipeCard> {
        let rows = try SQLRequest<Row>(
            literal: "SELECT " + columns + " " + source(query, grouped: false) + " ORDER BY " + order(query)
                + " LIMIT \(limit)"
        ).fetchAll(db)
        var cards = rows.map(card)
        let categories = try categoryIDs(db, recipes: cards.map(\.id))
        for index in cards.indices {
            cards[index].categoryIDs = categories[cards[index].id] ?? []
        }
        let total = try SQLRequest<Int>(literal: "SELECT COUNT(*) " + source(query, grouped: false)).fetchOne(db) ?? 0
        return ListPage(rows: cards, total: total)
    }

    static func gallery(_ db: Database, _ query: RecipeGalleryQuery, limit: Int) throws -> ListPage<GalleryItem> {
        let source = source(query.recipes, grouped: true, collapsed: query.collapsed)
        let order: SQL = "cat.position IS NULL, cat.position, cat.id, " + order(query.recipes)
        let rows = try SQLRequest<Row>(
            literal: "SELECT rc.categoryId AS groupId, " + columns + " " + source + " ORDER BY " + order
                + " LIMIT \(limit)"
        ).fetchAll(db)
        let items = rows.map { GalleryItem(categoryID: $0["groupId"], card: card($0)) }
        let total = try SQLRequest<Int>(literal: "SELECT COUNT(*) " + source).fetchOne(db) ?? 0
        return ListPage(rows: items, total: total)
    }

    /// The gallery's groups in order, with how many recipes each holds: collapsed groups count too.
    static func groups(_ db: Database, _ query: RecipeQuery) throws -> [RecipeGroup] {
        let rows = try SQLRequest<Row>(
            literal: "SELECT rc.categoryId AS categoryId, COUNT(*) AS count " + source(query, grouped: true)
                + " GROUP BY rc.categoryId ORDER BY cat.position IS NULL, cat.position, rc.categoryId"
        ).fetchAll(db)
        return rows.map { RecipeGroup(categoryID: $0["categoryId"], count: $0["count"]) }
    }

    private static let columns: SQL = """
        recipe.id, recipe.title, recipe.photo, recipe.videoURL, recipe.isFavorite, recipe.servings, \
        stats.totalMinutes, stats.kcalPer100, stats.kcalPerServing, stats.proteinPerServing, stats.fatPerServing, \
        stats.carbsPerServing, stats.isNutritionComplete
        """

    private static func card(_ row: Row) -> RecipeCard {
        var perServing: Nutrition?
        if let kcal: Double = row["kcalPerServing"], let protein: Double = row["proteinPerServing"],
            let fat: Double = row["fatPerServing"], let carbs: Double = row["carbsPerServing"]
        {
            perServing = Nutrition(kcal: kcal, protein: protein, fat: fat, carbs: carbs)
        }
        return RecipeCard(
            id: row["id"], title: row["title"], photo: row["photo"], hasVideo: (row["videoURL"] as String?) != nil,
            isFavorite: row["isFavorite"], servings: row["servings"], totalMinutes: row["totalMinutes"],
            kcalPer100: row["kcalPer100"], perServing: perServing, isNutritionComplete: row["isNutritionComplete"])
    }

    private static func categoryIDs(_ db: Database, recipes: [Recipe.ID]) throws -> [Recipe.ID: [RecipeCategory.ID]] {
        guard !recipes.isEmpty else { return [:] }
        let rows = try SQLRequest<Row>(
            literal: """
                SELECT recipe_category.recipeId, recipe_category.categoryId FROM recipe_category
                JOIN category ON category.id = recipe_category.categoryId
                WHERE recipe_category.recipeId IN \(recipes) ORDER BY category.position, category.id
                """
        ).fetchAll(db)
        var result: [Recipe.ID: [RecipeCategory.ID]] = [:]
        for row in rows {
            result[row["recipeId"], default: []].append(row["categoryId"])
        }
        return result
    }

    private static func source(
        _ query: RecipeQuery, grouped: Bool, collapsed: Set<RecipeCategory.ID?> = []
    ) -> SQL {
        var sql: SQL = "FROM recipe JOIN recipe_stats AS stats ON stats.recipeId = recipe.id"
        if let pattern = ProductListSQL.matchPattern(query.text) {
            // The full-text search stays the outer loop, as with products.
            sql = """
                FROM (SELECT rowid AS matchId, rank AS matchRank FROM recipe_ft WHERE recipe_ft MATCH \(pattern))
                AS found CROSS JOIN recipe ON recipe.id = found.matchId
                JOIN recipe_stats AS stats ON stats.recipeId = recipe.id
                """
        }
        if grouped {
            sql += """
                 LEFT JOIN recipe_category AS rc ON rc.recipeId = recipe.id
                 LEFT JOIN category AS cat ON cat.id = rc.categoryId
                """
        }
        var conditions: [SQL] = ["recipe.deletedAt IS NULL"]
        if !query.categoryIDs.isEmpty {
            let ids = query.categoryIDs.sorted()
            conditions.append(
                grouped
                    ? "rc.categoryId IN \(ids)"
                    : """
                    EXISTS (SELECT 1 FROM recipe_category WHERE recipe_category.recipeId = recipe.id
                    AND recipe_category.categoryId IN \(ids))
                    """)
        }
        if !query.mealTypeIDs.isEmpty {
            conditions.append(
                """
                EXISTS (SELECT 1 FROM recipe_meal_type WHERE recipe_meal_type.recipeId = recipe.id
                AND recipe_meal_type.mealTypeId IN \(query.mealTypeIDs.sorted()))
                """)
        }
        for product in query.withProducts.sorted() {
            conditions.append(
                """
                EXISTS (SELECT 1 FROM recipe_ingredient WHERE recipe_ingredient.recipeId = recipe.id
                AND recipe_ingredient.productId = \(product))
                """)
        }
        if !query.withoutProducts.isEmpty {
            conditions.append(
                """
                NOT EXISTS (SELECT 1 FROM recipe_ingredient WHERE recipe_ingredient.recipeId = recipe.id
                AND recipe_ingredient.productId IN \(query.withoutProducts.sorted()))
                """)
        }
        let ranges: [(String, ValueRange)] = [
            ("stats.kcalPerServing", query.kcalPerServing), ("stats.proteinPerServing", query.protein),
            ("stats.fatPerServing", query.fat), ("stats.carbsPerServing", query.carbs),
        ]
        for (column, range) in ranges {
            if let min = range.min { conditions.append(SQL(sql: "\(column) >= ?", arguments: [min])) }
            if let max = range.max { conditions.append(SQL(sql: "\(column) <= ?", arguments: [max])) }
        }
        if let maxMinutes = query.maxMinutes {
            conditions.append("stats.totalMinutes <= \(maxMinutes)")
        }
        if let isFavorite = query.isFavorite {
            conditions.append("recipe.isFavorite = \(isFavorite)")
        }
        if let hasPhoto = query.hasPhoto {
            conditions.append("(recipe.photo IS NOT NULL) = \(hasPhoto)")
        }
        if let hasVideo = query.hasVideo {
            conditions.append("(recipe.videoURL IS NOT NULL) = \(hasVideo)")
        }
        if let incomplete = query.nutritionIncomplete {
            conditions.append("stats.isNutritionComplete = \(!incomplete)")
        }
        let hidden = collapsed.compactMap { $0 }.sorted()
        if !hidden.isEmpty {
            conditions.append("rc.categoryId IS NULL OR rc.categoryId NOT IN \(hidden)")
        }
        if collapsed.contains(nil) {
            conditions.append("rc.categoryId IS NOT NULL")
        }
        return sql + " WHERE " + conditions.map { "(" + $0 + ")" }.joined(separator: " AND ")
    }

    /// Built from the keys alone. Empty values go last either way.
    private static func order(_ query: RecipeQuery) -> SQL {
        var terms: [String] = []
        let searching = ProductListSQL.matchPattern(query.text) != nil
        for term in query.sort {
            let direction = term.direction == .ascending ? "ASC" : "DESC"
            let column: String? =
                switch term.key {
                case .title: "stats.titleKey"
                case .kcalPer100: "stats.kcalPer100"
                case .kcalPerServing: "stats.kcalPerServing"
                case .protein: "stats.proteinPerServing"
                case .fat: "stats.fatPerServing"
                case .carbs: "stats.carbsPerServing"
                case .totalTime: "stats.totalMinutes"
                case .createdAt: "recipe.createdAt"
                case .updatedAt: "recipe.updatedAt"
                case .relevance: searching ? "found.matchRank" : nil
                }
            guard let column else { continue }
            terms += ["\(column) IS NULL", "\(column) \(direction)"]
        }
        terms += ["stats.titleKey ASC", "recipe.id ASC"]
        return SQL(sql: terms.joined(separator: ", "))
    }
}
