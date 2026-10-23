import Foundation
import MealCore

/// Numbers the way the interface writes them: Russian decimal commas, whatever the Mac's region.
enum Formatting {
    static let locale = Locale(identifier: "ru_RU")

    /// For text fields: up to three decimals, no thousands separators to trip over while typing.
    static let decimal = FloatingPointFormatStyle<Double>.number.locale(locale).grouping(.never)
        .precision(.fractionLength(0...3))

    /// «12,6», «0,5», «143»; a dash when there is no value.
    static func number(_ value: Double?, digits: Int = 1) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.locale(locale).precision(.fractionLength(0...digits)))
    }

    /// «1 240 продуктов».
    static func count(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(count.formatted(.number.locale(locale))) \(RussianPlural.form(for: Double(count), one: one, few: few, many: many))"
    }
}
