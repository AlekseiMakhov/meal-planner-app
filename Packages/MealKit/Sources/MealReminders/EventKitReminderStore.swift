import EventKit
import Foundation
import MealCore

/// «Напоминания» through EventKit. Reminders in iCloud reach the iPhones of everyone the list is shared with.
@MainActor
public final class EventKitReminderStore: ReminderStore {
    public let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    /// Asks once; macOS remembers the answer, and Privacy settings change it later.
    public func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    public func lists() throws -> [ReminderList] {
        store.calendars(for: .reminder).map { list in
            ReminderList(id: list.calendarIdentifier, title: list.title, account: list.source.title)
        }
        .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    public func createList(named name: String) throws -> ReminderList {
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = name
        guard
            let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV })
                ?? store.sources.first(where: { $0.sourceType == .local })
        else { throw ReminderStoreError("Нет учётной записи для «Напоминаний».") }
        list.source = source
        try store.saveCalendar(list, commit: true)
        return ReminderList(id: list.calendarIdentifier, title: list.title, account: source.title)
    }

    public func reminders(in listID: String) async throws -> [ReminderItem] {
        guard let list = store.calendar(withIdentifier: listID) else {
            throw ReminderStoreError("Списка в «Напоминаниях» больше нет: выберите другой в Настройках.")
        }
        let predicate = store.predicateForReminders(in: [list])
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.item))
            }
        }
    }

    public func create(_ reminder: ReminderItem, in listID: String) throws -> String {
        guard let list = store.calendar(withIdentifier: listID) else {
            throw ReminderStoreError("Списка в «Напоминаниях» больше нет: выберите другой в Настройках.")
        }
        let new = EKReminder(eventStore: store)
        new.calendar = list
        Self.apply(reminder, to: new)
        try store.save(new, commit: true)
        return new.calendarItemIdentifier
    }

    public func update(_ reminder: ReminderItem) throws {
        guard let existing = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        Self.apply(reminder, to: existing)
        try store.save(existing, commit: true)
    }

    public func delete(id: String) throws {
        guard let existing = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try store.remove(existing, commit: true)
    }

    private nonisolated static func item(_ reminder: EKReminder) -> ReminderItem {
        let due = reminder.dueDateComponents.flatMap { parts -> Day? in
            guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
            return Day(year: year, month: month, day: day)
        }
        return ReminderItem(
            id: reminder.calendarItemIdentifier, title: reminder.title ?? "", notes: reminder.notes, url: reminder.url,
            isCompleted: reminder.isCompleted, dueDay: due)
    }

    private static func apply(_ item: ReminderItem, to reminder: EKReminder) {
        reminder.title = item.title
        reminder.notes = item.notes
        reminder.url = item.url
        reminder.isCompleted = item.isCompleted
        reminder.dueDateComponents = item.dueDay.map { DateComponents(year: $0.year, month: $0.month, day: $0.day) }
    }
}
