import Foundation

/// A tag colour after Notion's palette; the app draws each with a colour token.
public enum TagColor: String, CaseIterable, Codable, Hashable, Sendable {
    case gray, brown, orange, yellow, green, blue, purple, pink, red

    public var title: String {
        switch self {
        case .gray: "Серый"
        case .brown: "Коричневый"
        case .orange: "Оранжевый"
        case .yellow: "Жёлтый"
        case .green: "Зелёный"
        case .blue: "Синий"
        case .purple: "Фиолетовый"
        case .pink: "Розовый"
        case .red: "Красный"
        }
    }
}

/// A group of recipes: «Завтраки», «Супы», «Быстрые». A recipe can be in several.
public struct RecipeCategory: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    public var color: TagColor
    public var position: Int

    public init(id: Int64, name: String, color: TagColor = .gray, position: Int = 0) {
        self.id = id
        self.name = name
        self.color = color
        self.position = position
    }
}

/// Breakfast, lunch, dinner, snack: the rows of the week's menu and what a recipe suits.
public struct MealType: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    public var color: TagColor
    public var position: Int

    public init(id: Int64, name: String, color: TagColor, position: Int) {
        self.id = id
        self.name = name
        self.color = color
        self.position = position
    }
}

public struct Recipe: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var title: String
    /// The photo's file name in the app's image folder.
    public var photo: String?
    /// A video page or an `<iframe>` code; see `VideoEmbed`.
    public var videoURL: String?
    public var sourceURL: String?
    /// How many servings the ingredients make.
    public var servings: Int
    /// The finished dish's weight, when known: calories per 100 g come out right only with it.
    public var yieldGrams: Double?
    public var prepMinutes: Int?
    public var cookMinutes: Int?
    public var notes: String
    /// Per 100 g as the source gives it; replaces what the ingredients add up to.
    public var nutritionOverride: Nutrition?
    public var isFavorite: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// When the recipe went to the trash; it is deleted for good 30 days later.
    public var deletedAt: Date?

    public static let defaultServings = 2

    public init(
        id: Int64, title: String, photo: String? = nil, videoURL: String? = nil, sourceURL: String? = nil,
        servings: Int = Recipe.defaultServings, yieldGrams: Double? = nil, prepMinutes: Int? = nil,
        cookMinutes: Int? = nil, notes: String = "", nutritionOverride: Nutrition? = nil, isFavorite: Bool = false,
        createdAt: Date = .now, updatedAt: Date = .now, deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.photo = photo
        self.videoURL = videoURL
        self.sourceURL = sourceURL
        self.servings = servings
        self.yieldGrams = yieldGrams
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.notes = notes
        self.nutritionOverride = nutritionOverride
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Preparation and cooking together; nil when neither is known.
    public var totalMinutes: Int? {
        guard prepMinutes != nil || cookMinutes != nil else { return nil }
        return (prepMinutes ?? 0) + (cookMinutes ?? 0)
    }
}

/// One line of a recipe's ingredients. The id lives only in memory, to keep rows apart while editing.
public struct RecipeIngredient: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var productID: Product.ID
    /// Nil for «по вкусу» and «для жарки».
    public var amount: Double?
    /// The upper end of a range: 3 in «2–3 зубчика».
    public var amountMax: Double?
    /// Nil with an amount means pieces.
    public var unit: MeasureUnit?
    public var note: String?
    /// A heading the line sits under: «Для соуса».
    public var group: String?
    public var isOptional: Bool

    public init(
        id: UUID = UUID(), productID: Product.ID, amount: Double? = nil, amountMax: Double? = nil,
        unit: MeasureUnit? = nil, note: String? = nil, group: String? = nil, isOptional: Bool = false
    ) {
        self.id = id
        self.productID = productID
        self.amount = amount
        self.amountMax = amountMax
        self.unit = unit
        self.note = note
        self.group = group
        self.isOptional = isOptional
    }

    /// The unit the amount is in: pieces when a number stands alone.
    public var effectiveUnit: MeasureUnit? {
        unit ?? (amount == nil ? nil : .piece)
    }

    /// The amount for `servings` when the recipe makes `of`: «3 яйца на 2 порции» is 4,5 на 3.
    public func scaled(to servings: Int, of original: Int) -> RecipeIngredient {
        guard original > 0, servings != original else { return self }
        let factor = Double(servings) / Double(original)
        var scaled = self
        scaled.amount = amount.map { $0 * factor }
        scaled.amountMax = amountMax.map { $0 * factor }
        return scaled
    }

    /// The weight that counts toward nutrition: the middle of a range. Nil when the line has no amount or
    /// the product cannot weigh its unit.
    public func grams(of product: Product) -> Double? {
        guard let amount, let unit = effectiveUnit, unit.kind != .unmeasured else { return nil }
        let middle = amountMax.map { (amount + $0) / 2 } ?? amount
        return product.units.grams(middle, unit)
    }

    /// Whether the line has an amount at all: salt to taste does not count against complete nutrition.
    public var isMeasured: Bool {
        amount != nil && effectiveUnit?.kind != .unmeasured
    }
}

public struct RecipeStep: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// A recipe with everything it is made of, as the page shows it and the editor changes it.
public struct RecipeDetails: Hashable, Sendable {
    public var recipe: Recipe
    public var ingredients: [RecipeIngredient]
    public var steps: [RecipeStep]
    /// In the categories' own order.
    public var categoryIDs: [RecipeCategory.ID]
    public var mealTypeIDs: Set<MealType.ID>
    /// The products the ingredients use, for their names, units and nutrition. Not saved with the recipe.
    public var products: [Product.ID: Product]

    public init(
        recipe: Recipe, ingredients: [RecipeIngredient] = [], steps: [RecipeStep] = [],
        categoryIDs: [RecipeCategory.ID] = [], mealTypeIDs: Set<MealType.ID> = [], products: [Product.ID: Product] = [:]
    ) {
        self.recipe = recipe
        self.ingredients = ingredients
        self.steps = steps
        self.categoryIDs = categoryIDs
        self.mealTypeIDs = mealTypeIDs
        self.products = products
    }

    public var nutrition: RecipeNutrition {
        RecipeNutrition(
            ingredients: ingredients, products: products, servings: recipe.servings, finishedWeight: recipe.yieldGrams,
            override: recipe.nutritionOverride)
    }

    /// Why the recipe cannot be saved as it is; empty when it can.
    public var problems: [String] {
        var problems: [String] = []
        if recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("Нужно название.")
        }
        if !(1...100).contains(recipe.servings) {
            problems.append("Порций — от 1 до 100.")
        }
        if let yield = recipe.yieldGrams, yield <= 0 {
            problems.append("Вес готового блюда должен быть больше нуля.")
        }
        if [recipe.prepMinutes, recipe.cookMinutes].contains(where: { ($0 ?? 0) < 0 }) {
            problems.append("Время не бывает отрицательным.")
        }
        if ingredients.contains(where: { ($0.amount ?? 0) < 0 || ($0.amountMax ?? 0) < 0 }) {
            problems.append("Количество не бывает отрицательным.")
        }
        if let override = recipe.nutritionOverride,
            let problem = Product(
                id: 0, name: "-", kcal: override.kcal, protein: override.protein, fat: override.fat,
                carbs: override.carbs
            ).problems.first
        {
            problems.append(problem.description)
        }
        return problems
    }
}

/// What a recipe's ingredients add up to, or what its source says per 100 g.
public struct RecipeNutrition: Hashable, Sendable {
    public let total: NutritionTotal
    public let per100g: Nutrition?
    public let perServing: Nutrition?
    /// The source's values were used rather than the ingredients'.
    public let isFromSource: Bool

    public init(
        ingredients: [RecipeIngredient], products: [Product.ID: Product], servings: Int, finishedWeight: Double?,
        override: Nutrition?
    ) {
        var total = NutritionTotal()
        for ingredient in ingredients where ingredient.isMeasured {
            let product = products[ingredient.productID]
            total.add(product?.nutrition, grams: product.flatMap { ingredient.grams(of: $0) })
        }
        self.total = total
        if let override {
            isFromSource = true
            per100g = override
            let weight = finishedWeight ?? total.grams
            perServing = weight > 0 && servings > 0 ? override.inGrams(weight) * (1 / Double(servings)) : nil
        } else {
            isFromSource = false
            per100g = total.per100g(finishedWeight: finishedWeight)
            perServing = total.perServing(servings)
        }
    }

    /// Whether every measured ingredient counted; values from the source are complete by definition.
    public var isComplete: Bool {
        isFromSource || total.isComplete
    }
}
