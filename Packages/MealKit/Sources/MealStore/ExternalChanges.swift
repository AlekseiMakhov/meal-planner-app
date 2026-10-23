import CoreFoundation
import Foundation
import GRDB

/// Writes from the other process — the MCP server while the app shows the data — reach the app's lists: the
/// writer posts a Darwin notification, the app asks its observations to fetch again. SQLite itself tells
/// nothing to other connections.
public enum ExternalChanges {
    public static let name = "inco.mealplanner.changed"

    /// Tells every process watching that the database changed.
    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }
}

/// Calls the handler whenever another process posts `ExternalChanges`; stops when released.
public final class ExternalChangesObserver: Sendable {
    private let handler: @Sendable () -> Void

    public init(_ handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<ExternalChangesObserver>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            ExternalChanges.name as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }
}

extension AppDatabase {
    /// Makes this process's observations fetch again: another process wrote to the file.
    public func notifyExternalChanges() throws {
        try writer.write { db in try db.notifyChanges(in: .fullDatabase) }
    }

    /// A number that changes whenever another process commits, and only then: compared when the app comes
    /// back to the front, it catches a notification the app missed.
    public func dataVersion() throws -> Int {
        try writer.writeWithoutTransaction { db in try Int.fetchOne(db, sql: "PRAGMA data_version") ?? 0 }
    }
}
