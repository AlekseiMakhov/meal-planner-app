/// Calories and macronutrients, per 100 g of a food unless said otherwise.
public struct Nutrition: Hashable, Sendable, Codable {
    public var kcal: Double
    public var protein: Double
    public var fat: Double
    public var carbs: Double

    public init(kcal: Double, protein: Double, fat: Double, carbs: Double) {
        self.kcal = kcal
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
    }

    public static let zero = Nutrition(kcal: 0, protein: 0, fat: 0, carbs: 0)

    /// What `grams` of the food contain, for nutrition given per 100 g.
    public func inGrams(_ grams: Double) -> Nutrition {
        self * (grams / 100)
    }

    public static func + (lhs: Nutrition, rhs: Nutrition) -> Nutrition {
        Nutrition(
            kcal: lhs.kcal + rhs.kcal, protein: lhs.protein + rhs.protein, fat: lhs.fat + rhs.fat,
            carbs: lhs.carbs + rhs.carbs)
    }

    public static func * (lhs: Nutrition, factor: Double) -> Nutrition {
        Nutrition(
            kcal: lhs.kcal * factor, protein: lhs.protein * factor, fat: lhs.fat * factor, carbs: lhs.carbs * factor)
    }

    /// The general Atwater factors: 4 kcal per gram of protein and of carbohydrate, 9 per gram of fat.
    public var kcalFromMacros: Double {
        4 * protein + 9 * fat + 4 * carbs
    }

    /// Whether the calories agree with the macronutrients within 15 % or 10 kcal: a hint at a typo. Foods with
    /// much fibre, organic acids or alcohol legitimately fall outside it.
    public var caloriesMatchMacros: Bool {
        abs(kcal - kcalFromMacros) <= max(0.15 * kcal, 10)
    }
}

/// Adds up the nutrition of a dish's ingredients and keeps count of the ones it could not include: those
/// without nutrition or without a weight.
public struct NutritionTotal: Hashable, Sendable {
    public private(set) var nutrition = Nutrition.zero
    /// The raw weight of the ingredients counted.
    public private(set) var grams = 0.0
    public private(set) var counted = 0
    public private(set) var ingredients = 0

    public init() {}

    /// One ingredient: its nutrition per 100 g and its weight. Ingredients without an amount, such as salt
    /// to taste, are left out by the caller and do not count against completeness.
    public mutating func add(_ per100g: Nutrition?, grams: Double?) {
        ingredients += 1
        guard let per100g, let grams else { return }
        nutrition = nutrition + per100g.inGrams(grams)
        self.grams += grams
        counted += 1
    }

    public var isComplete: Bool {
        counted == ingredients
    }

    /// Per 100 g of the dish: by the finished weight when it is known, else by the raw ingredients' weight.
    public func per100g(finishedWeight: Double? = nil) -> Nutrition? {
        let weight = finishedWeight ?? grams
        guard weight > 0 else { return nil }
        return nutrition * (100 / weight)
    }

    public func perServing(_ servings: Int) -> Nutrition? {
        guard servings > 0, counted > 0 else { return nil }
        return nutrition * (1 / Double(servings))
    }
}
