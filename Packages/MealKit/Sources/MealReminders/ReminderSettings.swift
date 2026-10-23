import Foundation
import MealCore

/// How the shopping list looks in «Напоминания»: Settings → «Напоминания».
public struct ReminderSettings: Codable, Hashable, Sendable {
    public enum TitleStyle: String, Codable, CaseIterable, Sendable {
        /// «Молоко — 1 л».
        case nameAndAmount
        /// «Молоко»; the amount goes to the note.
        case nameOnly
    }

    public var isEnabled = false
    /// The list to keep in step with; nil until one is chosen.
    public var listID: String?
    public var titleStyle = TitleStyle.nameAndAmount
    /// «🥛 Молоко — 1 л»: sorted by title in «Напоминания», items of an aisle stand together.
    public var aisleEmoji = false
    public var notesDishes = true
    public var notesDays = false
    /// The day of the week to shop, 1 for Monday … 7 for Sunday: reminders fall due on the next one.
    public var shoppingWeekday: Int?
    /// Bought items leave the list this many days after; nil — only when cleared by hand.
    public var clearBoughtAfterDays: Int?
    /// Takes in what the family adds to the list on their iPhones.
    public var acceptsFamilyItems = true

    public init() {}

    /// The day reminders fall due: the next shopping day from `today`, today included.
    public func dueDay(from today: Day) -> Day? {
        guard let weekday = shoppingWeekday, (1...7).contains(weekday) else { return nil }
        return today.adding(days: (weekday - today.weekday + 7) % 7)
    }
}

/// The words of a shopping item in «Напоминания».
public enum ReminderText {
    /// «Молоко — 545 мл», «🥛 Молоко — 545 мл» or «Молоко».
    public static func title(_ entry: ShoppingEntry, settings: ReminderSettings, aisle: String?) -> String {
        var title = entry.name
        if settings.titleStyle == .nameAndAmount, let amount = entry.item.amount {
            title += " — " + AmountText.quantity(amount, entry.item.unit ?? .piece)
        }
        if settings.aisleEmoji {
            title = emoji(for: aisle) + " " + title
        }
        return title
    }

    /// «для: Омлет, Сырники», with days «(ПН, СР)» and the amount when the title leaves it out.
    public static func notes(_ entry: ShoppingEntry, settings: ReminderSettings) -> String? {
        var lines: [String] = []
        if settings.titleStyle == .nameOnly, let amount = entry.item.amount {
            lines.append(AmountText.quantity(amount, entry.item.unit ?? .piece))
        }
        if settings.notesDishes {
            var titles: [String] = []
            for reason in entry.item.reasons where !titles.contains(reason.title) {
                titles.append(reason.title)
            }
            if !titles.isEmpty {
                var line = "для: " + titles.joined(separator: ", ")
                if settings.notesDays {
                    let days = Set(entry.item.reasons.compactMap { $0.day.flatMap(Day.init) }).sorted()
                    if !days.isEmpty {
                        line += " (" + days.map { weekdays[$0.weekday - 1] }.joined(separator: ", ") + ")"
                    }
                }
                lines.append(line)
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// A title as the family types it, without the aisle's emoji: «🥛 Молоко — 1 л» → «Молоко — 1 л».
    public static func plain(_ title: String) -> String {
        String(title.drop { !$0.isLetter && !$0.isNumber }).trimmingCharacters(in: .whitespaces)
    }

    static let weekdays = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"]

    /// The aisles of the starting base by the words of their names; others get a basket.
    static func emoji(for aisle: String?) -> String {
        let name = SearchText.normalized(aisle ?? "")
        let marks: [(String, String)] = [
            ("овощ", "🥬"), ("фрукт", "🍎"), ("хлеб", "🍞"), ("молоч", "🥛"), ("сыр", "🧀"), ("мяс", "🥩"),
            ("колбас", "🥓"), ("рыб", "🐟"), ("круп", "🌾"), ("мука", "🧁"), ("масл", "🫒"), ("специ", "🧂"),
            ("консерв", "🥫"), ("орех", "🥜"), ("заморож", "🧊"), ("сладост", "🍫"), ("напит", "🧃"),
        ]
        return marks.first { name.contains($0.0) }?.1 ?? "🛒"
    }
}
