import Foundation
import MealCore

/// A reminder as the sync sees it: plain values, whatever store holds it.
public struct ReminderItem: Hashable, Sendable {
    /// The store's identifier; empty until the reminder is saved.
    public var id: String
    public var title: String
    public var notes: String?
    /// Meal Planner's link to its shopping item, `mealplanner://shopping/12`; nil on a reminder someone else added.
    public var url: URL?
    public var isCompleted: Bool
    /// The day to shop, as the reminder's due date.
    public var dueDay: Day?

    public init(
        id: String = "", title: String, notes: String? = nil, url: URL? = nil, isCompleted: Bool = false,
        dueDay: Day? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.url = url
        self.isCompleted = isCompleted
        self.dueDay = dueDay
    }
}

/// A list in «Напоминания».
public struct ReminderList: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    /// The account it is in: «iCloud», «На Mac».
    public var account: String

    public init(id: String, title: String, account: String) {
        self.id = id
        self.title = title
        self.account = account
    }
}

/// Where reminders live: EventKit on the Mac, a fake in tests.
@MainActor
public protocol ReminderStore: AnyObject {
    func lists() throws -> [ReminderList]
    /// A new list in the account new reminders go to — iCloud, so the family can be given it.
    func createList(named name: String) throws -> ReminderList
    func reminders(in listID: String) async throws -> [ReminderItem]
    /// Saves a new reminder and returns its identifier.
    func create(_ reminder: ReminderItem, in listID: String) throws -> String
    func update(_ reminder: ReminderItem) throws
    func delete(id: String) throws
}

public struct ReminderStoreError: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
