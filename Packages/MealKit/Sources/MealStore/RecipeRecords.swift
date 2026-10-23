import Foundation
import GRDB
import MealCore

struct CategoryRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "category"

    var id: Int64?
    var name: String
    var color: String
    var position: Int

    init(_ category: RecipeCategory, id: Int64?) {
        self.id = id
        name = category.name
        color = category.color.rawValue
        position = category.position
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var category: RecipeCategory {
        RecipeCategory(id: id ?? 0, name: name, color: TagColor(rawValue: color) ?? .gray, position: position)
    }
}

struct MealTypeRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meal_type"

    var id: Int64
    var key: String?
    var name: String
    var color: String
    var position: Int

    var mealType: MealType {
        MealType(id: id, name: name, color: TagColor(rawValue: color) ?? .gray, position: position)
    }
}

struct RecipeRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "recipe"

    var id: Int64?
    var title: String
    var photo: String?
    var videoURL: String?
    var sourceURL: String?
    var servings: Int
    var yieldGrams: Double?
    var prepMinutes: Int?
    var cookMinutes: Int?
    var notes: String
    var overrideKcal: Double?
    var overrideProtein: Double?
    var overrideFat: Double?
    var overrideCarbs: Double?
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(_ recipe: Recipe, id: Int64?) {
        self.id = id
        title = recipe.title
        photo = recipe.photo
        videoURL = recipe.videoURL.flatMap { $0.isEmpty ? nil : $0 }
        sourceURL = recipe.sourceURL.flatMap { $0.isEmpty ? nil : $0 }
        servings = recipe.servings
        yieldGrams = recipe.yieldGrams
        prepMinutes = recipe.prepMinutes
        cookMinutes = recipe.cookMinutes
        notes = recipe.notes
        overrideKcal = recipe.nutritionOverride?.kcal
        overrideProtein = recipe.nutritionOverride?.protein
        overrideFat = recipe.nutritionOverride?.fat
        overrideCarbs = recipe.nutritionOverride?.carbs
        isFavorite = recipe.isFavorite
        createdAt = recipe.createdAt
        updatedAt = recipe.updatedAt
        deletedAt = recipe.deletedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var recipe: Recipe {
        var override: Nutrition?
        if let overrideKcal, let overrideProtein, let overrideFat, let overrideCarbs {
            override = Nutrition(kcal: overrideKcal, protein: overrideProtein, fat: overrideFat, carbs: overrideCarbs)
        }
        return Recipe(
            id: id ?? 0, title: title, photo: photo, videoURL: videoURL, sourceURL: sourceURL, servings: servings,
            yieldGrams: yieldGrams, prepMinutes: prepMinutes, cookMinutes: cookMinutes, notes: notes,
            nutritionOverride: override, isFavorite: isFavorite, createdAt: createdAt, updatedAt: updatedAt,
            deletedAt: deletedAt)
    }
}

struct RecipeIngredientRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "recipe_ingredient"

    var id: Int64?
    var recipeId: Int64
    var productId: Int64
    var amount: Double?
    var amountMax: Double?
    var unit: String?
    var note: String?
    var groupName: String?
    var isOptional: Bool
    var position: Int

    init(_ ingredient: RecipeIngredient, recipeID: Int64, position: Int) {
        recipeId = recipeID
        productId = ingredient.productID
        amount = ingredient.amount
        amountMax = ingredient.amountMax
        unit = ingredient.unit?.rawValue
        note = ingredient.note.flatMap(Self.text)
        groupName = ingredient.group.flatMap(Self.text)
        isOptional = ingredient.isOptional
        self.position = position
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var ingredient: RecipeIngredient {
        RecipeIngredient(
            productID: productId, amount: amount, amountMax: amountMax, unit: unit.flatMap(MeasureUnit.init(rawValue:)),
            note: note, group: groupName, isOptional: isOptional)
    }

    /// Trimmed, or nil when nothing is left.
    private static func text(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct RecipeStepRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "recipe_step"

    var id: Int64?
    var recipeId: Int64
    var position: Int
    var text: String

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct RecipeCategoryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recipe_category"

    var recipeId: Int64
    var categoryId: Int64
}

struct RecipeMealTypeRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recipe_meal_type"

    var recipeId: Int64
    var mealTypeId: Int64
}

struct RecipeStatsRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recipe_stats"

    var recipeId: Int64
    var titleKey: String
    var searchText: String
    var kcalPer100: Double?
    var kcalPerServing: Double?
    var proteinPerServing: Double?
    var fatPerServing: Double?
    var carbsPerServing: Double?
    var totalMinutes: Int?
    var isNutritionComplete: Bool
}
