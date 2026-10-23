import Foundation
import GRDB
import MealCore

/// Reading whole recipes, and the derived values lists sort and filter by: nutrition per serving, total time
/// and the search text. Those live in `recipe_stats` and are refreshed whenever a recipe or one of its
/// products changes, inside the same transaction.
enum RecipeDerived {
    static func details(_ db: Database, id: Recipe.ID) throws -> RecipeDetails? {
        guard let record = try RecipeRecord.fetchOne(db, key: id) else { return nil }
        let ingredientRows = try RecipeIngredientRecord.filter(Column("recipeId") == id).order(Column("position"))
            .fetchAll(db)
        let ingredients = ingredientRows.map { row in
            var ingredient = row.ingredient
            ingredient.id = UUID(stable: row.id ?? 0)
            return ingredient
        }
        let steps = try RecipeStepRecord.filter(Column("recipeId") == id).order(Column("position")).fetchAll(db)
            .map { RecipeStep(id: UUID(stable: $0.id ?? 0), text: $0.text) }
        let categoryIDs = try Int64.fetchAll(
            db,
            sql: """
                SELECT recipe_category.categoryId FROM recipe_category
                JOIN category ON category.id = recipe_category.categoryId
                WHERE recipe_category.recipeId = ? ORDER BY category.position, category.id
                """, arguments: [id])
        let mealTypeIDs = try Int64.fetchSet(
            db, sql: "SELECT mealTypeId FROM recipe_meal_type WHERE recipeId = ?", arguments: [id])
        let products = try ProductRecord.fetchAll(db, keys: Set(ingredientRows.map(\.productId))).map(\.product)
        return RecipeDetails(
            recipe: record.recipe, ingredients: ingredients, steps: steps, categoryIDs: categoryIDs,
            mealTypeIDs: mealTypeIDs, products: Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) }))
    }

    static func refresh(_ db: Database, recipeIDs: some Sequence<Recipe.ID>) throws {
        for id in Set(recipeIDs) {
            guard let details = try details(db, id: id) else { continue }
            let nutrition = details.nutrition
            let products = details.ingredients.compactMap { details.products[$0.productID] }
            let words =
                [details.recipe.title, details.recipe.notes] + details.steps.map(\.text)
                + products.flatMap { [$0.name] + $0.aliases } + details.ingredients.compactMap(\.note)
            try RecipeStatsRecord(
                recipeId: id, titleKey: SearchText.normalized(details.recipe.title),
                searchText: SearchText.normalized(words.joined(separator: " ")), kcalPer100: nutrition.per100g?.kcal,
                kcalPerServing: nutrition.perServing?.kcal, proteinPerServing: nutrition.perServing?.protein,
                fatPerServing: nutrition.perServing?.fat, carbsPerServing: nutrition.perServing?.carbs,
                totalMinutes: details.recipe.totalMinutes, isNutritionComplete: nutrition.isComplete
            ).upsert(db)
        }
    }

    /// The recipes a product is in, trashed ones included: they come back with the product as it is now.
    static func recipes(using productID: Product.ID, _ db: Database) throws -> [Recipe.ID] {
        try Int64.fetchAll(
            db, sql: "SELECT DISTINCT recipeId FROM recipe_ingredient WHERE productId = ?", arguments: [productID])
    }
}

extension UUID {
    /// The same UUID for the same row on every read, so lists keep their rows while nothing changed.
    init(stable number: Int64) {
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: number.bigEndian) { for (index, byte) in $0.enumerated() { bytes[8 + index] = byte } }
        self.init(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
                bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}
