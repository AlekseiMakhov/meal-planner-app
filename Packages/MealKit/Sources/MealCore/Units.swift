/// A unit an amount is written in. The raw value is what the database stores.
public enum MeasureUnit: String, CaseIterable, Codable, Hashable, Sendable {
    case gram = "g"
    case kilogram = "kg"
    case milliliter = "ml"
    case liter = "l"
    case teaspoon = "tsp"
    case tablespoon = "tbsp"
    case cup
    case piece = "pcs"
    case clove, bunch, slice, sprig, leaf, head, can, pack, handful
    case pinch
    case toTaste = "to-taste"

    public enum Kind: Hashable, Sendable {
        /// Converts to grams by a fixed factor.
        case mass(grams: Double)
        /// Converts to millilitres by a fixed factor. Spoons and cups are level metric measures.
        case volume(milliliters: Double)
        /// A whole piece of the product: an egg, an onion.
        case piece
        /// A part only the product itself can weigh: a clove of garlic, a bunch of dill, a can.
        case named
        /// No amount to speak of: a pinch, to taste.
        case unmeasured
    }

    public var kind: Kind {
        switch self {
        case .gram: .mass(grams: 1)
        case .kilogram: .mass(grams: 1000)
        case .milliliter: .volume(milliliters: 1)
        case .liter: .volume(milliliters: 1000)
        case .teaspoon: .volume(milliliters: 5)
        case .tablespoon: .volume(milliliters: 15)
        case .cup: .volume(milliliters: 250)
        case .piece: .piece
        case .clove, .bunch, .slice, .sprig, .leaf, .head, .can, .pack, .handful: .named
        case .pinch, .toTaste: .unmeasured
        }
    }

    /// The units a product can give its own weight for, in the order the editor offers them.
    public static let named: [MeasureUnit] = allCases.filter { $0.kind == .named }

    /// Abbreviations stay as they are; words agree with the number: «1 стакан», «2 стакана», «5 стаканов».
    public func title(for amount: Double) -> String {
        guard let forms = wordForms else { return symbol }
        return RussianPlural.form(for: amount, one: forms.one, few: forms.few, many: forms.many)
    }

    /// The short form: in table headers, pickers and next to numbers.
    public var symbol: String {
        switch self {
        case .gram: "г"
        case .kilogram: "кг"
        case .milliliter: "мл"
        case .liter: "л"
        case .teaspoon: "ч. л."
        case .tablespoon: "ст. л."
        case .piece: "шт."
        case .toTaste: "по вкусу"
        default: wordForms?.one ?? rawValue
        }
    }

    private var wordForms: (one: String, few: String, many: String)? {
        switch self {
        case .cup: ("стакан", "стакана", "стаканов")
        case .clove: ("зубчик", "зубчика", "зубчиков")
        case .bunch: ("пучок", "пучка", "пучков")
        case .slice: ("ломтик", "ломтика", "ломтиков")
        case .sprig: ("веточка", "веточки", "веточек")
        case .leaf: ("лист", "листа", "листов")
        case .head: ("головка", "головки", "головок")
        case .can: ("банка", "банки", "банок")
        case .pack: ("упаковка", "упаковки", "упаковок")
        case .handful: ("горсть", "горсти", "горстей")
        case .pinch: ("щепотка", "щепотки", "щепоток")
        default: nil
        }
    }
}

/// The unit a product is kept and counted in: what the pantry stores and the shopping list adds up.
public enum BaseUnit: String, CaseIterable, Codable, Hashable, Sendable {
    case gram = "g"
    case milliliter = "ml"
    case piece = "pcs"

    public var unit: MeasureUnit {
        switch self {
        case .gram: .gram
        case .milliliter: .milliliter
        case .piece: .piece
        }
    }
}

/// Russian noun forms after a number.
public enum RussianPlural {
    /// «1 продукт», «2 продукта», «5 продуктов»; a fraction takes the form for two: «1,5 стакана».
    public static func form(for amount: Double, one: String, few: String, many: String) -> String {
        guard amount.rounded() == amount, abs(amount) < Double(Int.max) else { return few }
        let number = abs(Int(amount))
        switch (number % 10, number % 100) {
        case (1, let tens) where tens != 11: return one
        case (2...4, let tens) where !(12...14).contains(tens): return few
        default: return many
        }
    }
}
