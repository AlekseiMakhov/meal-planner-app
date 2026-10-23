/// From–to, either end optional: «до 300 ккал», «от 20 г белка».
public struct ValueRange: Hashable, Sendable {
    public var min: Double?
    public var max: Double?

    public init(min: Double? = nil, max: Double? = nil) {
        self.min = min
        self.max = max
    }

    public var isEmpty: Bool {
        min == nil && max == nil
    }
}

/// What the recipe gallery and the nutrition table show: search, filters and order. Nutrition filters are per
/// serving.
public struct RecipeQuery: Hashable, Sendable {
    public enum SortKey: String, CaseIterable, Hashable, Sendable {
        case title, kcalPer100, kcalPerServing, protein, fat, carbs, totalTime, createdAt, updatedAt
        /// How well the recipe matches the search; without a search, the title.
        case relevance
    }

    public var text: String
    /// Recipes in any of these categories; empty — in any or none.
    public var categoryIDs: Set<RecipeCategory.ID>
    /// Recipes suiting any of these meals.
    public var mealTypeIDs: Set<MealType.ID>
    /// Recipes with every one of these products.
    public var withProducts: Set<Product.ID>
    /// Recipes with none of these products: «без молока».
    public var withoutProducts: Set<Product.ID>
    public var kcalPerServing: ValueRange
    public var protein: ValueRange
    public var fat: ValueRange
    public var carbs: ValueRange
    /// Preparation and cooking together, at most.
    public var maxMinutes: Int?
    public var isFavorite: Bool?
    public var hasPhoto: Bool?
    public var hasVideo: Bool?
    /// Recipes some of whose ingredients the nutrition could not count.
    public var nutritionIncomplete: Bool?
    public var sort: [SortTerm<SortKey>]

    public init(
        text: String = "", categoryIDs: Set<RecipeCategory.ID> = [], mealTypeIDs: Set<MealType.ID> = [],
        withProducts: Set<Product.ID> = [], withoutProducts: Set<Product.ID> = [], kcalPerServing: ValueRange = .init(),
        protein: ValueRange = .init(), fat: ValueRange = .init(), carbs: ValueRange = .init(), maxMinutes: Int? = nil,
        isFavorite: Bool? = nil, hasPhoto: Bool? = nil, hasVideo: Bool? = nil, nutritionIncomplete: Bool? = nil,
        sort: [SortTerm<SortKey>] = [SortTerm(.title)]
    ) {
        self.text = text
        self.categoryIDs = categoryIDs
        self.mealTypeIDs = mealTypeIDs
        self.withProducts = withProducts
        self.withoutProducts = withoutProducts
        self.kcalPerServing = kcalPerServing
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.maxMinutes = maxMinutes
        self.isFavorite = isFavorite
        self.hasPhoto = hasPhoto
        self.hasVideo = hasVideo
        self.nutritionIncomplete = nutritionIncomplete
        self.sort = sort
    }

    /// How many filters are on; the search does not count.
    public var filterCount: Int {
        [
            !categoryIDs.isEmpty, !mealTypeIDs.isEmpty, !withProducts.isEmpty, !withoutProducts.isEmpty,
            !kcalPerServing.isEmpty, !protein.isEmpty, !fat.isEmpty, !carbs.isEmpty, maxMinutes != nil,
            isFavorite != nil, hasPhoto != nil, hasVideo != nil, nutritionIncomplete != nil,
        ].filter { $0 }.count
    }

    /// The same query without filters, keeping the search and the order.
    public var withoutFilters: RecipeQuery {
        RecipeQuery(text: text, sort: sort)
    }
}

/// A recipe as lists show it: the gallery's card and the nutrition table's row.
public struct RecipeCard: Identifiable, Hashable, Sendable {
    public var id: Recipe.ID
    public var title: String
    public var photo: String?
    public var hasVideo: Bool
    public var isFavorite: Bool
    public var servings: Int
    public var totalMinutes: Int?
    public var kcalPer100: Double?
    /// Calories and macronutrients in one serving.
    public var perServing: Nutrition?
    public var isNutritionComplete: Bool
    public var categoryIDs: [RecipeCategory.ID]

    public init(
        id: Recipe.ID, title: String, photo: String? = nil, hasVideo: Bool = false, isFavorite: Bool = false,
        servings: Int = Recipe.defaultServings, totalMinutes: Int? = nil, kcalPer100: Double? = nil,
        perServing: Nutrition? = nil, isNutritionComplete: Bool = true, categoryIDs: [RecipeCategory.ID] = []
    ) {
        self.id = id
        self.title = title
        self.photo = photo
        self.hasVideo = hasVideo
        self.isFavorite = isFavorite
        self.servings = servings
        self.totalMinutes = totalMinutes
        self.kcalPer100 = kcalPer100
        self.perServing = perServing
        self.isNutritionComplete = isNutritionComplete
        self.categoryIDs = categoryIDs
    }
}

/// The gallery groups recipes by category, as Notion does; a recipe in two categories shows in both groups.
public struct RecipeGalleryQuery: Hashable, Sendable {
    public var recipes: RecipeQuery
    /// Groups whose cards are hidden; nil stands for the recipes without a category.
    public var collapsed: Set<RecipeCategory.ID?>

    public init(recipes: RecipeQuery = RecipeQuery(), collapsed: Set<RecipeCategory.ID?> = []) {
        self.recipes = recipes
        self.collapsed = collapsed
    }
}

/// A card in its category's group.
public struct GalleryItem: Identifiable, Hashable, Sendable {
    /// Nil for recipes without a category, which come last.
    public var categoryID: RecipeCategory.ID?
    public var card: RecipeCard

    public init(categoryID: RecipeCategory.ID?, card: RecipeCard) {
        self.categoryID = categoryID
        self.card = card
    }

    public var id: String {
        "\(categoryID.map(String.init) ?? "none")-\(card.id)"
    }
}

/// A category with the number of its recipes outside the trash: the sidebar's list.
public struct CategorySummary: Identifiable, Hashable, Sendable {
    public var category: RecipeCategory
    public var count: Int

    public init(category: RecipeCategory, count: Int) {
        self.category = category
        self.count = count
    }

    public var id: RecipeCategory.ID {
        category.id
    }
}

/// A gallery group and how many recipes it holds under the current search and filters.
public struct RecipeGroup: Hashable, Sendable {
    public var categoryID: RecipeCategory.ID?
    public var count: Int

    public init(categoryID: RecipeCategory.ID?, count: Int) {
        self.categoryID = categoryID
        self.count = count
    }
}
