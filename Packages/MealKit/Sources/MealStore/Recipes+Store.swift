import Foundation
import GRDB
import MealCore

extension AppDatabase {
    // MARK: - Categories

    public func categories() throws -> [RecipeCategory] {
        try reader.read { db in try CategoryRecord.order(Column("position"), Column("id")).fetchAll(db).map(\.category)
        }
    }

    /// Categories with how many recipes outside the trash each holds: the sidebar's list.
    public func categorySummaries() throws -> [CategorySummary] {
        try reader.read { db in try Self.fetchCategorySummaries(db) }
    }

    public func observeCategories() -> AsyncValueObservation<[CategorySummary]> {
        ValueObservation.trackingConstantRegion { db in try Self.fetchCategorySummaries(db) }
            .removeDuplicates().values(in: reader)
    }

    private static func fetchCategorySummaries(_ db: Database) throws -> [CategorySummary] {
        let counts = try Row.fetchAll(
            db,
            sql: """
                SELECT recipe_category.categoryId AS id, COUNT(*) AS count FROM recipe_category
                JOIN recipe ON recipe.id = recipe_category.recipeId AND recipe.deletedAt IS NULL
                GROUP BY recipe_category.categoryId
                """
        ).reduce(into: [Int64: Int]()) { result, row in result[row["id"]] = row["count"] }
        return try CategoryRecord.order(Column("position"), Column("id")).fetchAll(db).map {
            CategorySummary(category: $0.category, count: counts[$0.id ?? 0] ?? 0)
        }
    }

    /// A new category at the end of the list, in the next colour of the palette.
    public func newCategory(named name: String) throws -> RecipeCategory {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StoreError("Нужно название.") }
        return try writer.write { db in
            try Self.checkCategoryName(name, except: nil, db)
            let count = try CategoryRecord.fetchCount(db)
            let colors = TagColor.allCases.filter { $0 != .gray }
            var record = CategoryRecord(
                RecipeCategory(id: 0, name: name, color: colors[count % colors.count], position: count), id: nil)
            try record.insert(db)
            return record.category
        }
    }

    /// Renames or recolours a category; its place in the list stays.
    @discardableResult
    public func save(_ category: RecipeCategory) throws -> RecipeCategory {
        var category = category
        category.name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.name.isEmpty else { throw StoreError("Нужно название.") }
        return try writer.write { db in
            guard let record = try CategoryRecord.fetchOne(db, key: category.id) else {
                throw StoreError("Категории больше нет.")
            }
            try Self.checkCategoryName(category.name, except: category.id, db)
            category.position = record.position
            try CategoryRecord(category, id: category.id).update(db)
            return category
        }
    }

    /// Removes the category; its recipes stay, in their other categories or without one.
    public func deleteCategory(id: RecipeCategory.ID) throws {
        try writer.write { db in
            _ = try CategoryRecord.deleteOne(db, key: id)
        }
    }

    /// Puts the categories in this order.
    public func reorderCategories(_ ids: [RecipeCategory.ID]) throws {
        try writer.write { db in
            for (position, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE category SET position = ? WHERE id = ?", arguments: [position, id])
            }
        }
    }

    private static func checkCategoryName(_ name: String, except id: Int64?, _ db: Database) throws {
        let key = SearchText.normalized(name)
        for record in try CategoryRecord.fetchAll(db) where record.id != id && SearchText.normalized(record.name) == key
        {
            throw StoreError("Категория «\(record.name)» уже есть.")
        }
    }

    // MARK: - Meal types

    public func mealTypes() throws -> [MealType] {
        try reader.read { db in try MealTypeRecord.order(Column("position")).fetchAll(db).map(\.mealType) }
    }

    // MARK: - Reading recipes

    public func recipe(id: Recipe.ID) throws -> RecipeDetails? {
        try reader.read { db in try RecipeDerived.details(db, id: id) }
    }

    /// The recipe with its products, kept current: a product's new nutrition shows on the page at once.
    public func observeRecipe(id: Recipe.ID) -> AsyncValueObservation<RecipeDetails?> {
        ValueObservation.trackingConstantRegion { db in try RecipeDerived.details(db, id: id) }
            .removeDuplicates().values(in: reader)
    }

    public func recipeCards(_ query: RecipeQuery, limit: Int, offset: Int = 0) throws -> ListPage<RecipeCard> {
        try reader.read { db in try RecipeListSQL.cards(db, query, limit: limit, offset: offset) }
    }

    /// The nutrition table's rows.
    public func observeRecipeCards(_ query: RecipeQuery, limit: Int) -> AsyncValueObservation<ListPage<RecipeCard>> {
        ValueObservation.trackingConstantRegion { db in try RecipeListSQL.cards(db, query, limit: limit) }
            .removeDuplicates().values(in: reader)
    }

    public func recipeGallery(_ query: RecipeGalleryQuery, limit: Int) throws -> ListPage<GalleryItem> {
        try reader.read { db in try RecipeListSQL.gallery(db, query, limit: limit) }
    }

    /// The gallery's cards, a card per recipe and category.
    public func observeRecipeGallery(
        _ query: RecipeGalleryQuery, limit: Int
    ) -> AsyncValueObservation<ListPage<GalleryItem>> {
        ValueObservation.trackingConstantRegion { db in try RecipeListSQL.gallery(db, query, limit: limit) }
            .removeDuplicates().values(in: reader)
    }

    /// The gallery's groups with their counts under the query.
    public func observeRecipeGroups(_ query: RecipeQuery) -> AsyncValueObservation<[RecipeGroup]> {
        ValueObservation.trackingConstantRegion { db in try RecipeListSQL.groups(db, query) }
            .removeDuplicates().values(in: reader)
    }

    // MARK: - Changing recipes

    /// A new empty recipe for two, in the given categories.
    public func newRecipe(in categoryIDs: [RecipeCategory.ID] = []) throws -> RecipeDetails {
        try writer.write { db in
            var record = RecipeRecord(Recipe(id: 0, title: "Новый рецепт"), id: nil)
            try record.insert(db)
            let id = record.id ?? 0
            for categoryID in categoryIDs {
                try RecipeCategoryRecord(recipeId: id, categoryId: categoryID).insert(db)
            }
            try RecipeDerived.refresh(db, recipeIDs: [id])
            return try RecipeDerived.details(db, id: id)!
        }
    }

    /// Adds a recipe that arrives complete, as Claude sends it: one transaction, so it shows up whole or not at all.
    public func newRecipe(from details: RecipeDetails) throws -> RecipeDetails {
        if let problem = details.problems.first {
            throw StoreError(problem)
        }
        return try writer.write { db in
            var recipe = details.recipe
            recipe.title = recipe.title.trimmingCharacters(in: .whitespacesAndNewlines)
            recipe.createdAt = .now
            recipe.updatedAt = .now
            recipe.deletedAt = nil
            var record = RecipeRecord(recipe, id: nil)
            try record.insert(db)
            let id = record.id ?? 0
            try Self.writeContent(of: details, to: id, db)
            return try RecipeDerived.details(db, id: id)!
        }
    }

    /// Saves the whole recipe: its fields, ingredient lines, steps, categories and meals. Empty steps are
    /// dropped. A replaced photo's file is removed once the recipe no longer refers to it.
    @discardableResult
    public func save(_ details: RecipeDetails) throws -> RecipeDetails {
        if let problem = details.problems.first {
            throw StoreError(problem)
        }
        let id = details.recipe.id
        let (saved, oldPhoto) = try writer.write { db -> (RecipeDetails, String?) in
            guard let record = try RecipeRecord.fetchOne(db, key: id) else { throw StoreError("Рецепта больше нет.") }
            var recipe = details.recipe
            recipe.title = recipe.title.trimmingCharacters(in: .whitespacesAndNewlines)
            recipe.createdAt = record.createdAt
            recipe.deletedAt = record.deletedAt
            recipe.updatedAt = .now
            try RecipeRecord(recipe, id: id).update(db)
            try Self.writeContent(of: details, to: id, db)
            let saved = try RecipeDerived.details(db, id: id)!
            return (saved, record.photo == recipe.photo ? nil : record.photo)
        }
        if let oldPhoto { images.delete(oldPhoto) }
        return saved
    }

    /// Replaces the recipe's ingredient lines, steps, categories and meals, then refreshes what lists show.
    private static func writeContent(of details: RecipeDetails, to id: Recipe.ID, _ db: Database) throws {
        try RecipeIngredientRecord.filter(Column("recipeId") == id).deleteAll(db)
        for (position, ingredient) in details.ingredients.enumerated() {
            guard try ProductRecord.exists(db, key: ingredient.productID) else {
                throw StoreError("Одного из продуктов больше нет: выберите его заново.")
            }
            var row = RecipeIngredientRecord(ingredient, recipeID: id, position: position)
            try row.insert(db)
        }
        try RecipeStepRecord.filter(Column("recipeId") == id).deleteAll(db)
        let steps = details.steps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for (position, text) in steps.enumerated() {
            var row = RecipeStepRecord(recipeId: id, position: position, text: text)
            try row.insert(db)
        }
        try RecipeCategoryRecord.filter(Column("recipeId") == id).deleteAll(db)
        for categoryID in Set(details.categoryIDs) where try CategoryRecord.exists(db, key: categoryID) {
            try RecipeCategoryRecord(recipeId: id, categoryId: categoryID).insert(db)
        }
        try RecipeMealTypeRecord.filter(Column("recipeId") == id).deleteAll(db)
        for mealTypeID in details.mealTypeIDs where try MealTypeRecord.exists(db, key: mealTypeID) {
            try RecipeMealTypeRecord(recipeId: id, mealTypeId: mealTypeID).insert(db)
        }
        try RecipeDerived.refresh(db, recipeIDs: [id])
    }

    public func setFavorite(_ isFavorite: Bool, recipeID: Recipe.ID) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE recipe SET isFavorite = ? WHERE id = ?", arguments: [isFavorite, recipeID])
        }
    }

    /// Puts the recipes into the category, or takes them out of it; their other categories stay. Without
    /// saving the recipes: the menus of the lists and a recipe dropped onto the sidebar do this.
    public func setCategory(_ categoryID: RecipeCategory.ID, isOn: Bool, recipeIDs: [Recipe.ID]) throws {
        try writer.write { db in
            guard try CategoryRecord.exists(db, key: categoryID) else { throw StoreError("Категории больше нет.") }
            for id in Set(recipeIDs) where try RecipeRecord.exists(db, key: id) {
                if isOn {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO recipe_category (recipeId, categoryId) VALUES (?, ?)",
                        arguments: [id, categoryID])
                } else {
                    try db.execute(
                        sql: "DELETE FROM recipe_category WHERE recipeId = ? AND categoryId = ?",
                        arguments: [id, categoryID])
                }
            }
        }
    }

    /// A copy of the recipe with its own photo, titled «… (копия)».
    public func duplicateRecipe(id: Recipe.ID) throws -> RecipeDetails {
        guard let original = try recipe(id: id) else { throw StoreError("Рецепта больше нет.") }
        let photo = try original.recipe.photo.map(images.copy)
        do {
            return try writer.write { db in
                var recipe = original.recipe
                recipe.title += " (копия)"
                recipe.photo = photo
                recipe.isFavorite = false
                recipe.createdAt = .now
                recipe.updatedAt = .now
                recipe.deletedAt = nil
                var record = RecipeRecord(recipe, id: nil)
                try record.insert(db)
                let copyID = record.id ?? 0
                try Self.writeContent(of: original, to: copyID, db)
                return try RecipeDerived.details(db, id: copyID)!
            }
        } catch {
            if let photo { images.delete(photo) }
            throw error
        }
    }

    /// Hides the recipe in the trash; it can be restored for 30 days.
    public func moveRecipeToTrash(id: Recipe.ID) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE recipe SET deletedAt = ? WHERE id = ?", arguments: [Date.now, id])
        }
    }

    public func restoreRecipe(id: Recipe.ID) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE recipe SET deletedAt = NULL WHERE id = ?", arguments: [id])
        }
    }

    /// The trash, the most recently deleted first.
    public func observeTrash() -> AsyncValueObservation<[Recipe]> {
        ValueObservation.trackingConstantRegion { db in
            try RecipeRecord.filter(Column("deletedAt") != nil).order(Column("deletedAt").desc).fetchAll(db)
                .map(\.recipe)
        }
        .removeDuplicates().values(in: reader)
    }

    /// Deletes the recipe and its photo for good.
    public func deleteRecipe(id: Recipe.ID) throws {
        let photo = try writer.write { db -> String? in
            let photo = try RecipeRecord.fetchOne(db, key: id)?.photo
            try RecipeRecord.deleteOne(db, key: id)
            return photo
        }
        if let photo { images.delete(photo) }
    }

    /// Deletes for good what has been in the trash longer than `days`; all of it with 0.
    @discardableResult
    public func emptyTrash(olderThan days: Int = 30) throws -> Int {
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
        let photos = try writer.write { db -> [String?] in
            let old = try RecipeRecord.filter(Column("deletedAt") != nil && Column("deletedAt") <= cutoff).fetchAll(db)
            try RecipeRecord.deleteAll(db, keys: old.compactMap(\.id))
            return old.map(\.photo)
        }
        for photo in photos.compactMap({ $0 }) { images.delete(photo) }
        return photos.count
    }

    /// Removes photo files no recipe refers to. Run at launch.
    @discardableResult
    public func removeUnusedImages() throws -> Int {
        let names = try reader.read { db in
            try String.fetchSet(db, sql: "SELECT photo FROM recipe WHERE photo IS NOT NULL")
        }
        return images.removeUnused(keeping: names)
    }
}
