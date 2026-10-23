import Foundation
import MealCore
import MealStore

/// What one round of the sync did.
public struct SyncReport: Hashable, Sendable {
    public var created = 0
    public var updated = 0
    public var deleted = 0
    public var imported = 0
    /// Items checked off on a phone: bought, waiting to go into the pantry.
    public var checkedElsewhere: [ShoppingItem.ID] = []
    public var uncheckedElsewhere = 0
    public var removedElsewhere = 0

    public init() {}

    public var changedApp: Bool {
        imported + checkedElsewhere.count + uncheckedElsewhere + removedElsewhere > 0
    }

    public var changedReminders: Bool {
        created + updated + deleted > 0
    }
}

/// Keeps the shopping list and a list in «Напоминания» in step, both ways. Each item has one reminder, linked by
/// its identifier and by the app's address in the reminder; the link remembers what the last round wrote, so a
/// difference shows which side changed. The app's list decides the wording; a phone decides what is checked off,
/// deleted or added, and an amount typed into a title there.
@MainActor
public final class ShoppingSync {
    public let database: AppDatabase
    public let store: any ReminderStore
    /// The app's URL scheme: «mealplanner», «mealplanner-debug» for a Debug build.
    public let scheme: String

    public init(database: AppDatabase, store: any ReminderStore, scheme: String) {
        self.database = database
        self.store = store
        self.scheme = scheme
    }

    @discardableResult
    public func sync(_ settings: ReminderSettings, today: Day = .today(), now: Date = .now) async throws -> SyncReport {
        guard settings.isEnabled, let listID = settings.listID else { return SyncReport() }
        var report = SyncReport()
        if let days = settings.clearBoughtAfterDays {
            try database.clearChecked(before: now.addingTimeInterval(-Double(days) * 86_400))
        }
        let reminders = try await store.reminders(in: listID)
        let byID = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let links = try database.reminderLinks()
        let aisles = Dictionary(uniqueKeysWithValues: try database.aisles().map { ($0.id, $0.name) })
        let due = settings.dueDay(from: today)
        var seen: Set<String> = []

        for original in try database.allShoppingEntries() {
            var entry = original
            let aisle = entry.product?.aisleID.flatMap { aisles[$0] }
            guard let link = links[entry.id] else {
                // New in the app; what was bought before the sync began stays out of «Напоминания».
                guard !entry.item.isChecked else { continue }
                let reminder = ReminderItem(
                    title: ReminderText.title(entry, settings: settings, aisle: aisle),
                    notes: ReminderText.notes(entry, settings: settings), url: url(for: entry.id), dueDay: due)
                let id = try store.create(reminder, in: listID)
                seen.insert(id)
                try database.saveReminderLink(
                    ReminderLink(itemID: entry.id, reminderID: id, title: reminder.title, isChecked: false))
                report.created += 1
                continue
            }
            guard var reminder = byID[link.reminderID] else {
                // Deleted in «Напоминания»: it leaves the app's list too.
                try database.removeShoppingItems([entry.id])
                report.removedElsewhere += 1
                continue
            }
            seen.insert(reminder.id)
            if reminder.isCompleted != link.isChecked, entry.item.isChecked == link.isChecked {
                try database.setChecked(reminder.isCompleted, items: [entry.id])
                entry.item.checkedAt = reminder.isCompleted ? now : nil
                if reminder.isCompleted {
                    report.checkedElsewhere.append(entry.id)
                } else {
                    report.uncheckedElsewhere += 1
                }
            }
            if reminder.title != link.title, let changed = try adopt(reminder.title, into: entry) {
                entry = changed
            }
            let title = ReminderText.title(entry, settings: settings, aisle: aisle)
            let notes = ReminderText.notes(entry, settings: settings)
            let checked = entry.item.isChecked
            let dueDay = checked ? reminder.dueDay : due
            let address = url(for: entry.id)
            if reminder.title != title || reminder.notes != notes || reminder.isCompleted != checked
                || reminder.url != address || reminder.dueDay != dueDay
            {
                reminder.title = title
                reminder.notes = notes
                reminder.isCompleted = checked
                reminder.url = address
                reminder.dueDay = dueDay
                try store.update(reminder)
                report.updated += 1
            }
            try database.saveReminderLink(
                ReminderLink(itemID: entry.id, reminderID: reminder.id, title: title, isChecked: checked))
        }

        let known = try database.knownReminderIDs()
        for reminder in reminders where !seen.contains(reminder.id) {
            if known.contains(reminder.id) || itemID(from: reminder.url) != nil {
                // Meal Planner's own reminder whose item left the list: bought and cleared, or deleted.
                try store.delete(id: reminder.id)
                report.deleted += 1
            } else if settings.acceptsFamilyItems, !reminder.isCompleted {
                try takeIn(reminder, settings: settings, aisles: aisles, due: due)
                report.imported += 1
            }
        }
        return report
    }

    // MARK: - Reminders added on a phone

    /// A reminder the family added — «хлеб», «2 л молока» — becomes an item: the product the name means, or text.
    /// An item not yet bought for the same thing grows instead, and the reminder goes, the item having its own.
    private func takeIn(
        _ reminder: ReminderItem, settings: ReminderSettings, aisles: [Int64: String], due: Day?
    ) throws {
        let text = ReminderText.plain(reminder.title)
        guard !text.isEmpty, let typed = try database.readLines(text).first else {
            try store.delete(id: reminder.id)
            return
        }
        var addition: ShoppingAddition
        if case .found(let product) = typed.match {
            addition = ShoppingAddition(product: product.id, amount: typed.amount, unit: typed.unit)
        } else {
            addition = ShoppingAddition(
                text: typed.name.prefix(1).uppercased() + typed.name.dropFirst(), amount: typed.amount, unit: typed.unit
            )
        }
        let existing = try database.openShoppingItemID(product: addition.productID, text: addition.text)
        let id = try database.addToShopping([addition]).first ?? existing
        guard let id else { return }
        if try existing != nil && database.reminderLinks()[id] != nil {
            try store.delete(id: reminder.id)
            return
        }
        guard let entry = try database.shoppingEntries(ids: [id]).first else { return }
        var linked = reminder
        linked.title = ReminderText.title(
            entry, settings: settings, aisle: entry.product?.aisleID.flatMap { aisles[$0] })
        linked.notes = ReminderText.notes(entry, settings: settings)
        linked.url = url(for: id)
        linked.dueDay = reminder.dueDay ?? due
        try store.update(linked)
        try database.saveReminderLink(
            ReminderLink(itemID: id, reminderID: linked.id, title: linked.title, isChecked: false))
    }

    /// A title edited on a phone: «Молоко — 2 л» sets the amount; a title without one leaves it as it was.
    private func adopt(_ title: String, into entry: ShoppingEntry) throws -> ShoppingEntry? {
        guard let typed = try database.readLines(ReminderText.plain(title)).first else { return nil }
        let amount = typed.amount ?? entry.item.amount
        let unit = typed.amount == nil ? entry.item.unit : typed.unit
        if let product = entry.product {
            guard case .found(let named) = typed.match, named.id == product.id else { return nil }
            try database.updateShoppingItem(entry.id, amount: amount, unit: unit)
        } else {
            try database.updateShoppingItem(entry.id, amount: amount, unit: unit, text: typed.name)
        }
        return try database.shoppingEntries(ids: [entry.id]).first
    }

    // MARK: - Addresses

    public func url(for id: ShoppingItem.ID) -> URL? {
        URL(string: "\(scheme)://shopping/\(id)")
    }

    public func itemID(from url: URL?) -> ShoppingItem.ID? {
        guard let url, url.scheme == scheme, url.host() == "shopping" else { return nil }
        return Int64(url.lastPathComponent)
    }
}
