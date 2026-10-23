import Foundation

/// A shop department. Products are grouped by them and the shopping list follows their order.
public struct Aisle: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    public var position: Int

    public init(id: Int64, name: String, position: Int) {
        self.id = id
        self.name = name
        self.position = position
    }
}

/// Where a product's calories and macronutrients come from.
public enum NutritionSource: String, CaseIterable, Codable, Hashable, Sendable {
    /// USDA FoodData Central; the note names the entry.
    case usda
    /// Typical values printed on packages.
    case label
    /// Reference tables.
    case reference
    case manual
    /// Filled in by Claude through the MCP server.
    case claude

    public var title: String {
        switch self {
        case .usda: "USDA"
        case .label: "Упаковка"
        case .reference: "Справочник"
        case .manual: "Вручную"
        case .claude: "Claude"
        }
    }
}

/// Something that goes into a dish, sits in the pantry or on the shopping list.
public struct Product: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    /// Other names and forms that find the product: «яйца» and «яиц» for «Яйцо куриное».
    public var aliases: [String]
    public var aisleID: Int64?
    /// Per 100 g; all four or none make sense, but each is kept as entered.
    public var kcal: Double?
    public var protein: Double?
    public var fat: Double?
    public var carbs: Double?
    public var baseUnit: BaseUnit
    public var gramsPerPiece: Double?
    public var density: Double?
    public var namedUnits: [MeasureUnit: Double]
    /// Salt, pepper, oil: what matters is whether it is in the house, not how many grams.
    public var isStaple: Bool
    public var nutritionSource: NutritionSource?
    public var sourceNote: String?
    public var needsReview: Bool
    /// The starting base's key for the product, if it came from there.
    public var seedKey: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64, name: String, aliases: [String] = [], aisleID: Int64? = nil, kcal: Double? = nil,
        protein: Double? = nil, fat: Double? = nil, carbs: Double? = nil, baseUnit: BaseUnit = .gram,
        gramsPerPiece: Double? = nil, density: Double? = nil, namedUnits: [MeasureUnit: Double] = [:],
        isStaple: Bool = false, nutritionSource: NutritionSource? = nil, sourceNote: String? = nil,
        needsReview: Bool = false, seedKey: String? = nil, createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.aisleID = aisleID
        self.kcal = kcal
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.baseUnit = baseUnit
        self.gramsPerPiece = gramsPerPiece
        self.density = density
        self.namedUnits = namedUnits
        self.isStaple = isStaple
        self.nutritionSource = nutritionSource
        self.sourceNote = sourceNote
        self.needsReview = needsReview
        self.seedKey = seedKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Complete nutrition per 100 g, or nil while any of the four values is missing.
    public var nutrition: Nutrition? {
        get {
            guard let kcal, let protein, let fat, let carbs else { return nil }
            return Nutrition(kcal: kcal, protein: protein, fat: fat, carbs: carbs)
        }
        set {
            kcal = newValue?.kcal
            protein = newValue?.protein
            fat = newValue?.fat
            carbs = newValue?.carbs
        }
    }

    public var units: UnitProfile {
        UnitProfile(baseUnit: baseUnit, gramsPerPiece: gramsPerPiece, density: density, namedUnits: namedUnits)
    }

    /// What the name is compared by: two products cannot share it.
    public var nameKey: String {
        SearchText.normalized(name)
    }

    /// The name and aliases as the search index keeps them.
    public var searchText: String {
        SearchText.normalized(([name] + aliases).joined(separator: " "))
    }
}

extension Product {
    public struct Problem: Error, Hashable, Sendable, CustomStringConvertible {
        public let description: String
    }

    /// The product with its name and aliases tidied: spaces trimmed, empty and repeated aliases dropped,
    /// along with any alias that only repeats the name.
    public func tidied() -> Product {
        var product = self
        product.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen: Set<String> = [product.nameKey]
        product.aliases = aliases.compactMap { alias in
            let alias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = SearchText.normalized(alias)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return alias
        }
        return product
    }

    /// Why the product cannot be saved as it is, in words for the editor; empty when it can.
    public var problems: [Problem] {
        var problems: [String] = []
        if nameKey.isEmpty {
            problems.append("Нужно название.")
        }
        let macros = [("Белки", protein), ("Жиры", fat), ("Углеводы", carbs)]
        if let kcal, !(0...902).contains(kcal) {
            problems.append("Калорийность на 100 г — от 0 до 900 ккал.")
        }
        for (title, value) in macros {
            if let value, !(0...100).contains(value) {
                problems.append("\(title) на 100 г — от 0 до 100 г.")
            }
        }
        if macros.compactMap(\.1).reduce(0, +) > 100.5 {
            problems.append("Белков, жиров и углеводов вместе больше 100 г на 100 г продукта.")
        }
        if let gramsPerPiece, gramsPerPiece <= 0 {
            problems.append("Вес одной штуки должен быть больше нуля.")
        }
        if let density, !(0.01...3).contains(density) {
            problems.append("Плотность — от 0,01 до 3 г/мл.")
        }
        if namedUnits.values.contains(where: { $0 <= 0 }) {
            problems.append("Вес единицы должен быть больше нуля.")
        }
        return problems.map(Problem.init)
    }
}
