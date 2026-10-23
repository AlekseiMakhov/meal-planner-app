public enum SortDirection: String, Hashable, Sendable, Codable {
    case ascending, descending

    public var reversed: SortDirection {
        self == .ascending ? .descending : .ascending
    }
}

/// One key of a list's order. Lists end their order with the name and the id, so rows with equal values
/// keep their places.
public struct SortTerm<Key: Hashable & Sendable>: Hashable, Sendable {
    public var key: Key
    public var direction: SortDirection

    public init(_ key: Key, _ direction: SortDirection = .ascending) {
        self.key = key
        self.direction = direction
    }
}

/// The rows loaded so far and how many the list has in all.
public struct ListPage<Row: Hashable & Sendable>: Hashable, Sendable {
    public var rows: [Row]
    public var total: Int

    public init(rows: [Row], total: Int) {
        self.rows = rows
        self.total = total
    }

    public static var empty: ListPage {
        ListPage(rows: [], total: 0)
    }
}

/// What the product list shows: search, filters and order. The app's screen and the MCP server ask for
/// products with the same query.
public struct ProductQuery: Hashable, Sendable {
    public enum SortKey: String, CaseIterable, Hashable, Sendable {
        case name, aisle, kcal, protein, fat, carbs, createdAt
        /// How many recipes use the product.
        case recipeCount
        /// How well the product matches the search; without a search, the name.
        case relevance
    }

    public enum NutritionState: String, CaseIterable, Hashable, Sendable {
        /// Some of the four values are missing.
        case missing
        case needsReview
        case complete
    }

    public var text: String
    /// Empty: every aisle, and products without one.
    public var aisleIDs: Set<Int64>
    public var isStaple: Bool?
    public var nutrition: NutritionState?
    public var kcal: ValueRange
    /// Products some recipe uses, or none does.
    public var isUsedInRecipes: Bool?
    /// Empty: any source, and none.
    public var sources: Set<NutritionSource>
    public var sort: [SortTerm<SortKey>]

    public init(
        text: String = "", aisleIDs: Set<Int64> = [], isStaple: Bool? = nil, nutrition: NutritionState? = nil,
        kcal: ValueRange = .init(), isUsedInRecipes: Bool? = nil, sources: Set<NutritionSource> = [],
        sort: [SortTerm<SortKey>] = [SortTerm(.name)]
    ) {
        self.text = text
        self.aisleIDs = aisleIDs
        self.isStaple = isStaple
        self.nutrition = nutrition
        self.kcal = kcal
        self.isUsedInRecipes = isUsedInRecipes
        self.sources = sources
        self.sort = sort
    }

    /// How many filters are on; the search does not count.
    public var filterCount: Int {
        [!aisleIDs.isEmpty, isStaple != nil, nutrition != nil, !kcal.isEmpty, isUsedInRecipes != nil, !sources.isEmpty]
            .filter { $0 }.count
    }

    /// The same query without filters, keeping the search and the order.
    public var withoutFilters: ProductQuery {
        ProductQuery(text: text, sort: sort)
    }
}
