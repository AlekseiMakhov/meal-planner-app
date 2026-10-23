import Foundation

/// A product kept at home and how much of it there is, in the product's base unit.
public struct PantryItem: Identifiable, Hashable, Sendable {
    public var productID: Product.ID
    /// In the product's base unit. Nil: there is some, uncounted — salt, oil, spices, or what nobody weighed.
    /// Zero: it ran out; the product stays in the pantry until it is removed.
    public var quantity: Double?
    /// Marked «заканчивается».
    public var isLow: Bool
    public var updatedAt: Date

    public init(productID: Product.ID, quantity: Double? = nil, isLow: Bool = false, updatedAt: Date = .now) {
        self.productID = productID
        self.quantity = quantity
        self.isLow = isLow
        self.updatedAt = updatedAt
    }

    public var id: Product.ID {
        productID
    }

    /// Whether there is any at all: a counted amount above zero, or some uncounted.
    public var isInStock: Bool {
        quantity.map { $0 > Self.tolerance } ?? true
    }

    public var status: PantryStatus {
        isInStock ? (isLow ? .low : .inStock) : .out
    }

    /// Amounts closer than this count as equal: what is left of 0,3 + 0,7 − 1 is no stock.
    public static let tolerance = 1e-6
}

public enum PantryStatus: String, CaseIterable, Hashable, Sendable {
    case inStock, low, out

    public var title: String {
        switch self {
        case .inStock: "Есть"
        case .low: "Заканчивается"
        case .out: "Закончилось"
        }
    }
}

/// Whether the pantry covers one ingredient line.
public enum Availability: Hashable, Sendable {
    case enough
    /// There is some, but `missing` more is needed, in the product's base unit.
    case low(missing: Double)
    /// None at home; `needed` is the line's amount in the product's base unit when it converts.
    case missing(needed: Double?)
    /// There is a counted amount, but the line's unit does not convert to it: «1 пучок» of dill counted in grams.
    case unknown

    /// Whether something has to be bought for the line.
    public var isShort: Bool {
        switch self {
        case .low, .missing: true
        case .enough, .unknown: false
        }
    }
}

extension RecipeIngredient {
    /// The amount to have at home: the top of a range, so «2–3 зубчика» asks for three.
    public var amountToHave: Double? {
        amountMax ?? amount
    }

    /// Whether `home` covers the line. A staple, and a line without an amount, only need the product to be there.
    public func availability(of product: Product, at home: PantryItem?) -> Availability {
        let present = home?.isInStock ?? false
        guard isMeasured, !product.isStaple, let amount = amountToHave, let unit = effectiveUnit else {
            return present ? .enough : .missing(needed: nil)
        }
        let needed = product.units.inBaseUnit(amount, unit)
        guard let home, present else { return .missing(needed: needed) }
        guard let have = home.quantity else { return .enough }
        guard let needed else { return .unknown }
        return have + PantryItem.tolerance >= needed ? .enough : .low(missing: needed - have)
    }

    /// What to buy so the pantry covers the line, for `reason`: the missing amount in the product's base unit, or
    /// the line's own amount when it does not convert. Nil when nothing has to be bought.
    public func shortage(of product: Product, at home: PantryItem?, reason: ShoppingReason?) -> ShoppingAddition? {
        switch availability(of: product, at: home) {
        case .enough, .unknown:
            return nil
        case .low(let missing):
            return ShoppingAddition(product: product.id, amount: missing, unit: product.baseUnit.unit, reason: reason)
        case .missing(let needed?):
            return ShoppingAddition(product: product.id, amount: needed, unit: product.baseUnit.unit, reason: reason)
        case .missing(nil):
            let measured = isMeasured && !product.isStaple
            return ShoppingAddition(
                product: product.id, amount: measured ? amountToHave : nil, unit: measured ? effectiveUnit : nil,
                reason: reason)
        }
    }
}

/// The pantry against a whole recipe.
public struct RecipeAvailability: Hashable, Sendable {
    public var lines: [RecipeIngredient.ID: Availability]
    /// Lines short of what the recipe needs; optional ones do not count.
    public var missingCount: Int
    /// Lines the pantry cannot be compared with.
    public var unknownCount: Int

    public init(lines: [RecipeIngredient.ID: Availability] = [:], missingCount: Int = 0, unknownCount: Int = 0) {
        self.lines = lines
        self.missingCount = missingCount
        self.unknownCount = unknownCount
    }
}

extension RecipeDetails {
    /// The pantry against the recipe made for `servings`, its own number unless asked.
    public func availability(servings: Int? = nil, pantry: [Product.ID: PantryItem]) -> RecipeAvailability {
        var result = RecipeAvailability()
        for line in ingredients {
            guard let product = products[line.productID] else { continue }
            let scaled = line.scaled(to: servings ?? recipe.servings, of: recipe.servings)
            let availability = scaled.availability(of: product, at: pantry[product.id])
            result.lines[line.id] = availability
            guard !line.isOptional else { continue }
            if availability.isShort {
                result.missingCount += 1
            } else if availability == .unknown {
                result.unknownCount += 1
            }
        }
        return result
    }

    /// Everything to buy for the recipe made for `servings`, optional lines aside.
    public func shortages(servings: Int? = nil, pantry: [Product.ID: PantryItem]) -> [ShoppingAddition] {
        let reason = ShoppingReason(recipeID: recipe.id, title: recipe.title)
        return ingredients.compactMap { line in
            guard !line.isOptional, let product = products[line.productID] else { return nil }
            return line.scaled(to: servings ?? recipe.servings, of: recipe.servings)
                .shortage(of: product, at: pantry[product.id], reason: reason)
        }
    }
}

// MARK: - Shopping

/// Why something is on the shopping list: a recipe, and in the week's menu the day it is for.
public struct ShoppingReason: Codable, Hashable, Sendable {
    public var recipeID: Recipe.ID?
    public var title: String
    /// The menu's day, «2026-10-23»; nil for a recipe bought for on its own.
    public var day: String?

    public init(recipeID: Recipe.ID? = nil, title: String, day: String? = nil) {
        self.recipeID = recipeID
        self.title = title
        self.day = day
    }
}

/// A line of the shopping list: a product of the base, or text for what is none («батарейки»).
public struct ShoppingItem: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var productID: Product.ID?
    public var text: String?
    public var amount: Double?
    public var unit: MeasureUnit?
    public var reasons: [ShoppingReason]
    public var checkedAt: Date?
    /// When the bought amount went into the pantry.
    public var stockedAt: Date?
    /// The manual order.
    public var position: Int
    public var createdAt: Date

    public init(
        id: Int64, productID: Product.ID? = nil, text: String? = nil, amount: Double? = nil, unit: MeasureUnit? = nil,
        reasons: [ShoppingReason] = [], checkedAt: Date? = nil, stockedAt: Date? = nil, position: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.productID = productID
        self.text = text
        self.amount = amount
        self.unit = unit
        self.reasons = reasons
        self.checkedAt = checkedAt
        self.stockedAt = stockedAt
        self.position = position
        self.createdAt = createdAt
    }

    public var isChecked: Bool {
        checkedAt != nil
    }
}

extension ShoppingItem {
    /// The item grown by `addition`: its reason joins the others and its amount adds up, converted through the
    /// product's units; the same reason twice adds nothing. Nil when the amounts do not add up — a bunch on top of
    /// grams with no weight for a bunch.
    public func adding(_ addition: ShoppingAddition, units: UnitProfile?) -> ShoppingItem? {
        var item = self
        if let reason = addition.reason {
            // Already on the list for this recipe and day: asking again adds nothing.
            guard !item.reasons.contains(reason) else { return item }
            item.reasons.append(reason)
        }
        guard let extra = addition.amount else { return item }
        guard let amount = item.amount else {
            item.amount = extra
            item.unit = addition.unit
            return item
        }
        let mine = item.unit ?? .piece
        let theirs = addition.unit ?? .piece
        guard let converted = (units ?? UnitProfile()).convert(extra, from: theirs, to: mine) else { return nil }
        item.amount = amount + converted
        return item
    }
}

/// Something to put on the shopping list: a product or a line of text, how much, and why. An item already
/// there for the same product grows instead of a second one appearing.
public struct ShoppingAddition: Hashable, Sendable {
    public var productID: Product.ID?
    public var text: String?
    public var amount: Double?
    public var unit: MeasureUnit?
    public var reason: ShoppingReason?

    public init(
        product: Product.ID? = nil, text: String? = nil, amount: Double? = nil, unit: MeasureUnit? = nil,
        reason: ShoppingReason? = nil
    ) {
        productID = product
        self.text = text
        self.amount = amount
        self.unit = unit
        self.reason = reason
    }
}

/// A pantry row as lists show it: the product with what there is of it.
public struct PantryEntry: Identifiable, Hashable, Sendable {
    public var product: Product
    public var item: PantryItem

    public init(product: Product, item: PantryItem) {
        self.product = product
        self.item = item
    }

    public var id: Product.ID {
        product.id
    }
}

/// A shopping row as lists show it: the item with its product, if it has one.
public struct ShoppingEntry: Identifiable, Hashable, Sendable {
    public var item: ShoppingItem
    public var product: Product?

    public init(item: ShoppingItem, product: Product? = nil) {
        self.item = item
        self.product = product
    }

    public var id: ShoppingItem.ID {
        item.id
    }

    public var name: String {
        product?.name ?? item.text ?? ""
    }

    /// The amount in the pantry's unit, what «в запасы» adds: nil when there is none or it does not convert.
    public var amountInBaseUnit: Double? {
        guard let product, let amount = item.amount else { return nil }
        guard let unit = item.unit else { return product.units.inBaseUnit(amount, .piece) }
        return product.units.inBaseUnit(amount, unit)
    }
}

/// What the pantry list shows: search, filters and order.
public struct PantryQuery: Hashable, Sendable {
    public enum SortKey: String, CaseIterable, Hashable, Sendable {
        case aisle, name, quantity, updatedAt
    }

    public var text: String
    /// Empty: every aisle, and products without one.
    public var aisleIDs: Set<Int64>
    /// Empty: any status.
    public var statuses: Set<PantryStatus>
    /// Products the dishes of the menu on these days still need: not cooked yet.
    public var menuDays: ClosedRange<Day>?
    public var sort: [SortTerm<SortKey>]

    public init(
        text: String = "", aisleIDs: Set<Int64> = [], statuses: Set<PantryStatus> = [],
        menuDays: ClosedRange<Day>? = nil,
        sort: [SortTerm<SortKey>] = [SortTerm(.aisle)]
    ) {
        self.text = text
        self.aisleIDs = aisleIDs
        self.statuses = statuses
        self.menuDays = menuDays
        self.sort = sort
    }

    public var filterCount: Int {
        [!aisleIDs.isEmpty, !statuses.isEmpty, menuDays != nil].filter { $0 }.count
    }

    public var withoutFilters: PantryQuery {
        PantryQuery(text: text, sort: sort)
    }
}

/// What the shopping list shows: search, filters and order. Bought items always come last.
public struct ShoppingQuery: Hashable, Sendable {
    public enum SortKey: String, CaseIterable, Hashable, Sendable {
        /// The aisles in the order of the shop, as one walks it.
        case aisle
        case name, createdAt
        /// The order the items were dragged into.
        case manual
    }

    public var text: String
    public var aisleIDs: Set<Int64>
    public var isChecked: Bool?
    /// Items wanted for this recipe.
    public var recipeID: Recipe.ID?
    /// Items wanted for this day of the week's menu, «2026-10-23».
    public var day: String?
    public var sort: [SortTerm<SortKey>]

    public init(
        text: String = "", aisleIDs: Set<Int64> = [], isChecked: Bool? = nil, recipeID: Recipe.ID? = nil,
        day: String? = nil, sort: [SortTerm<SortKey>] = [SortTerm(.aisle)]
    ) {
        self.text = text
        self.aisleIDs = aisleIDs
        self.isChecked = isChecked
        self.recipeID = recipeID
        self.day = day
        self.sort = sort
    }

    public var filterCount: Int {
        [!aisleIDs.isEmpty, isChecked != nil, recipeID != nil, day != nil].filter { $0 }.count
    }

    public var withoutFilters: ShoppingQuery {
        ShoppingQuery(text: text, sort: sort)
    }
}
