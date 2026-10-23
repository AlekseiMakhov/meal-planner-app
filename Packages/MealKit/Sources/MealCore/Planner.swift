import Foundation

/// A calendar day as the menu keeps it, «2026-10-23», in the Mac's own calendar and time zone. Weeks start on
/// Monday.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// «2026-10-23»; nil for anything else or a day that does not exist.
    public init?(_ text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        let day = Day(year: parts[0], month: parts[1], day: parts[2])
        guard Day(day.date()) == day else { return nil }
        self = day
    }

    public static func today(calendar: Calendar = .current) -> Day {
        Day(.now, calendar: calendar)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Noon of the day: far from midnight, so a change of daylight saving time cannot move it to another day.
    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    public func adding(days: Int, calendar: Calendar = .current) -> Day {
        Day(calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) ?? date(), calendar: calendar)
    }

    /// 1 for Monday … 7 for Sunday.
    public var weekday: Int {
        let sundayFirst = Calendar(identifier: .gregorian).component(.weekday, from: date())
        return (sundayFirst + 5) % 7 + 1
    }

    /// The Monday of the day's week.
    public var weekStart: Day {
        adding(days: 1 - weekday)
    }

    /// The ISO week number: «Неделя 43».
    public var weekNumber: Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: date())
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let day = Day(text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Не день: \(text)"))
        }
        self = day
    }
}

/// A dish in the week's menu: a recipe for so many servings, or text — «ужин в гостях».
public struct PlanEntry: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var day: Day
    public var mealTypeID: MealType.ID
    public var recipeID: Recipe.ID?
    public var text: String?
    public var servings: Int
    /// The order within its day and meal.
    public var position: Int
    public var cookedAt: Date?
    /// What «Приготовлено» took from the pantry, in the products' base units: given back on undo.
    public var used: [Product.ID: Double]

    public init(
        id: Int64, day: Day, mealTypeID: MealType.ID, recipeID: Recipe.ID? = nil, text: String? = nil,
        servings: Int = Recipe.defaultServings, position: Int = 0, cookedAt: Date? = nil,
        used: [Product.ID: Double] = [:]
    ) {
        self.id = id
        self.day = day
        self.mealTypeID = mealTypeID
        self.recipeID = recipeID
        self.text = text
        self.servings = servings
        self.position = position
        self.cookedAt = cookedAt
        self.used = used
    }

    public var isCooked: Bool {
        cookedAt != nil
    }
}

/// What a day of the menu adds up to: one serving of each dish for one person, and everything cooked.
public struct DayNutrition: Hashable, Sendable {
    public var perPerson = Nutrition.zero
    public var total = Nutrition.zero
    /// Dishes with a recipe whose nutrition is known.
    public var counted = 0
    /// Dishes left out: text, or a recipe without nutrition.
    public var uncounted = 0

    public init() {}

    public var isEmpty: Bool {
        counted == 0 && uncounted == 0
    }
}

/// The pantry spread over the menu in its order, from today on: the dishes it no longer covers and what to buy.
public struct MenuSupply: Hashable, Sendable {
    public var shortEntries: Set<PlanEntry.ID> = []
    /// One addition per short line, with the dish and its day as the reason.
    public var shortages: [ShoppingAddition] = []

    public init() {}
}

/// A week of the menu with the recipes its dishes use and what there is of their products at home.
public struct WeekPlan: Hashable, Sendable {
    public var start: Day
    public var mealTypes: [MealType]
    /// By day, meal and position.
    public var entries: [PlanEntry]
    public var recipes: [Recipe.ID: RecipeDetails]
    public var pantry: [Product.ID: PantryItem]

    public init(
        start: Day, mealTypes: [MealType] = [], entries: [PlanEntry] = [], recipes: [Recipe.ID: RecipeDetails] = [:],
        pantry: [Product.ID: PantryItem] = [:]
    ) {
        self.start = start
        self.mealTypes = mealTypes
        self.entries = entries
        self.recipes = recipes
        self.pantry = pantry
    }

    public var days: [Day] {
        (0..<7).map { start.adding(days: $0) }
    }

    public func entries(on day: Day, meal: MealType.ID) -> [PlanEntry] {
        entries.filter { $0.day == day && $0.mealTypeID == meal }
    }

    public func nutrition(on day: Day) -> DayNutrition {
        var result = DayNutrition()
        for entry in entries where entry.day == day {
            guard let recipe = entry.recipeID.flatMap({ recipes[$0] }), let serving = recipe.nutrition.perServing
            else {
                result.uncounted += 1
                continue
            }
            result.perPerson = result.perPerson + serving
            result.total = result.total + serving * Double(entry.servings)
            result.counted += 1
        }
        return result
    }

    /// The average of the days that have dishes; nil when none has.
    public var averageDay: DayNutrition? {
        let planned = days.map(nutrition(on:)).filter { $0.counted > 0 }
        guard !planned.isEmpty else { return nil }
        var result = DayNutrition()
        let share = 1 / Double(planned.count)
        for day in planned {
            result.perPerson = result.perPerson + day.perPerson * share
            result.total = result.total + day.total * share
            result.counted += day.counted
            result.uncounted += day.uncounted
        }
        return result
    }

    /// The pantry spent on the dishes in order, from `today` on; cooked dishes have already taken theirs.
    public func supply(from today: Day) -> MenuSupply {
        var supply = MenuSupply()
        var present = Set(pantry.values.filter(\.isInStock).map(\.productID))
        var amounts = pantry.values.reduce(into: [Product.ID: Double]()) { result, item in
            if item.isInStock, let quantity = item.quantity { result[item.productID] = quantity }
        }
        for entry in entries where entry.day >= today && !entry.isCooked {
            guard let recipe = entry.recipeID.flatMap({ recipes[$0] }) else { continue }
            let reason = ShoppingReason(
                recipeID: recipe.recipe.id, title: recipe.recipe.title, day: entry.day.description)
            for line in recipe.ingredients where !line.isOptional {
                guard let product = recipe.products[line.productID] else { continue }
                let scaled = line.scaled(to: entry.servings, of: recipe.recipe.servings)
                var addition: ShoppingAddition?
                if !scaled.isMeasured || product.isStaple {
                    if !present.contains(product.id) {
                        addition = ShoppingAddition(product: product.id, reason: reason)
                    }
                } else if let amount = scaled.amountToHave, let unit = scaled.effectiveUnit,
                    let need = product.units.inBaseUnit(amount, unit)
                {
                    if present.contains(product.id), amounts[product.id] == nil { continue }
                    let have = amounts[product.id] ?? 0
                    if have + PantryItem.tolerance >= need {
                        amounts[product.id] = have - need
                    } else {
                        amounts[product.id] = 0
                        addition = ShoppingAddition(
                            product: product.id, amount: need - have, unit: product.baseUnit.unit, reason: reason)
                    }
                } else if !present.contains(product.id) {
                    addition = ShoppingAddition(
                        product: product.id, amount: scaled.amountToHave, unit: scaled.effectiveUnit, reason: reason)
                }
                if let addition {
                    supply.shortEntries.insert(entry.id)
                    supply.shortages.append(addition)
                    // Once on the list, a product the next dishes only need to be there is covered; a counted amount
                    // keeps running short for each of them.
                    present.insert(product.id)
                }
            }
        }
        return supply
    }
}

/// What «Приготовлено» takes from the pantry for a dish: each counted product of its recipe and how much, in the
/// product's base unit.
public struct CookingUse: Identifiable, Hashable, Sendable {
    public var product: Product
    public var amount: Double
    /// What there is at home now; nil — some, uncounted.
    public var atHome: Double?

    public init(product: Product, amount: Double, atHome: Double?) {
        self.product = product
        self.amount = amount
        self.atHome = atHome
    }

    public var id: Product.ID {
        product.id
    }
}

extension RecipeDetails {
    /// What making the recipe for `servings` takes from the pantry: measured lines of counted products, optional
    /// ones included — the dialog lets them be corrected. Staples and lines to taste take nothing.
    public func cookingUse(servings: Int, pantry: [Product.ID: PantryItem]) -> [CookingUse] {
        var result: [Product.ID: CookingUse] = [:]
        var order: [Product.ID] = []
        for line in ingredients {
            guard let product = products[line.productID], !product.isStaple, line.isMeasured,
                let item = pantry[product.id], item.quantity != nil
            else { continue }
            let scaled = line.scaled(to: servings, of: recipe.servings)
            guard let amount = scaled.amountToHave, let unit = scaled.effectiveUnit,
                let base = product.units.inBaseUnit(amount, unit)
            else { continue }
            if result[product.id] == nil {
                order.append(product.id)
                result[product.id] = CookingUse(product: product, amount: 0, atHome: item.quantity)
            }
            result[product.id]?.amount += base
        }
        return order.compactMap { result[$0] }
    }
}
