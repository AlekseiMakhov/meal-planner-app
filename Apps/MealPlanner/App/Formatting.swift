import Foundation
import MealCore

/// Numbers the way the interface writes them: Russian decimal commas, whatever the Mac's region.
enum Formatting {
    static let locale = Locale(identifier: "ru_RU")

    /// For text fields: up to three decimals, no thousands separators to trip over while typing.
    static let decimal = FloatingPointFormatStyle<Double>.number.locale(locale).grouping(.never)
        .precision(.fractionLength(0...3))

    /// For whole numbers in text fields: minutes, grams of a finished dish.
    static let integer = IntegerFormatStyle<Int>.number.locale(locale).grouping(.never)

    /// «12,6», «0,5», «143»; a dash when there is no value.
    static func number(_ value: Double?, digits: Int = 1) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.locale(locale).precision(.fractionLength(0...digits)))
    }

    /// «1 240 продуктов».
    static func count(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(count.formatted(.number.locale(locale))) \(RussianPlural.form(for: Double(count), one: one, few: few, many: many))"
    }

    /// An ingredient's amount and unit: «3 шт.», «2–3 зубчика», «1,5 стакана», «по вкусу»; empty when the
    /// line has neither.
    static func amount(_ ingredient: RecipeIngredient) -> (amount: String, unit: String) {
        guard let unit = ingredient.effectiveUnit else { return ("", "") }
        guard let amount = ingredient.amount else { return ("", unit.kind == .unmeasured ? unit.symbol : "") }
        let value = number(amount, digits: amount < 10 ? 2 : 0)
        let text = ingredient.amountMax.map { "\(value)–\(number($0, digits: $0 < 10 ? 2 : 0))" } ?? value
        return (text, unit.title(for: ingredient.amountMax ?? amount))
    }

    /// An amount as people say it: «200 г», «1,5 кг», «750 мл», «1 л», «3 шт.», «1 пучок».
    static func quantity(_ value: Double, _ unit: MeasureUnit) -> String {
        AmountText.quantity(value, unit)
    }

    static let weekdays = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"]

    private static let months = [
        "января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября",
        "декабря",
    ]

    /// «19–25 октября», «28 сентября – 4 октября».
    static func week(_ start: Day) -> String {
        let end = start.adding(days: 6)
        if start.month == end.month {
            return "\(start.day)–\(end.day) \(months[end.month - 1])"
        }
        return "\(start.day) \(months[start.month - 1]) – \(end.day) \(months[end.month - 1])"
    }

    /// «23 октября».
    static func day(_ day: Day) -> String {
        "\(day.day) \(months[day.month - 1])"
    }

    /// «25 мин», «1 ч 30 мин».
    static func minutes(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) мин"
        case (_, 0): return "\(hours) ч"
        default: return "\(hours) ч \(rest) мин"
        }
    }

    /// «на 1 порцию», «на 2 порции», «на 5 порций».
    static func servings(_ count: Int) -> String {
        "на \(count) \(RussianPlural.form(for: Double(count), one: "порцию", few: "порции", many: "порций"))"
    }
}
