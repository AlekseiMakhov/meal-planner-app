import Foundation
import GRDB
import MealCore

/// What the last sync wrote to the reminder standing for a shopping item.
public struct ReminderLink: Hashable, Sendable {
    public var itemID: ShoppingItem.ID
    public var reminderID: String
    public var title: String
    public var isChecked: Bool

    public init(itemID: ShoppingItem.ID, reminderID: String, title: String, isChecked: Bool) {
        self.itemID = itemID
        self.reminderID = reminderID
        self.title = title
        self.isChecked = isChecked
    }
}

struct ReminderLinkRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "reminder_link"

    var shoppingItemId: Int64
    var reminderId: String
    var title: String
    var isChecked: Bool

    init(_ link: ReminderLink) {
        shoppingItemId = link.itemID
        reminderId = link.reminderID
        title = link.title
        isChecked = link.isChecked
    }

    var link: ReminderLink {
        ReminderLink(itemID: shoppingItemId, reminderID: reminderId, title: title, isChecked: isChecked)
    }
}

extension AppDatabase {
    public func reminderLinks() throws -> [ShoppingItem.ID: ReminderLink] {
        try reader.read { db in
            try ReminderLinkRecord.fetchAll(db).reduce(into: [:]) { result, record in
                result[record.shoppingItemId] = record.link
            }
        }
    }

    /// Records what the sync wrote; an item gone meanwhile has no link to keep.
    public func saveReminderLink(_ link: ReminderLink) throws {
        try writer.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO reminder_known (reminderId) VALUES (?)", arguments: [link.reminderID])
            guard try ShoppingItemRecord.exists(db, key: link.itemID) else { return }
            try db.execute(sql: "DELETE FROM reminder_link WHERE reminderId = ?", arguments: [link.reminderID])
            try ReminderLinkRecord(link).upsert(db)
        }
    }

    /// Reminders the app made or took in at some point.
    public func knownReminderIDs() throws -> Set<String> {
        try reader.read { db in try String.fetchSet(db, sql: "SELECT reminderId FROM reminder_known") }
    }

    /// The item not yet bought for the product, or with the text: where another «молоко» from the family goes.
    public func openShoppingItemID(product: Product.ID?, text: String?) throws -> ShoppingItem.ID? {
        try reader.read { db in
            if let product {
                return try Int64.fetchOne(
                    db, sql: "SELECT id FROM shopping_item WHERE productId = ? AND checkedAt IS NULL ORDER BY id",
                    arguments: [product])
            }
            guard let text, !text.isEmpty else { return nil }
            return try Int64.fetchOne(
                db,
                sql:
                    "SELECT id FROM shopping_item WHERE productId IS NULL AND textKey = ? AND checkedAt IS NULL ORDER BY id",
                arguments: [SearchText.normalized(text)])
        }
    }

    public func removeReminderLink(itemID: ShoppingItem.ID) throws {
        try writer.write { db in _ = try ReminderLinkRecord.deleteOne(db, key: itemID) }
    }

    /// Every item of the shopping list, bought ones included, in the list's own order.
    public func allShoppingEntries() throws -> [ShoppingEntry] {
        try reader.read { db in try ShoppingListSQL.page(db, ShoppingQuery(), limit: Int.max).rows }
    }

    /// Takes off the list what was bought before `date`: «удалять купленное через N дней».
    @discardableResult
    public func clearChecked(before date: Date) throws -> Int {
        try writer.write { db in
            try ShoppingItemRecord.filter(Column("checkedAt") != nil && Column("checkedAt") < date).deleteAll(db)
        }
    }
}
