import Foundation
import GRDB
import MealCore
import Testing

@testable import MealStore

struct BackupTests {
    private let folder = FileManager.default.temporaryDirectory.appending(
        path: "meal backups \(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func aCopyADayTheNewestFourteenKept() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try AppDatabase.open(in: folder.appending(path: "data", directoryHint: .isDirectory))
        _ = try database.newCategory(named: "Завтраки")
        let backups = Backups(folder: folder.appending(path: "Backups", directoryHint: .isDirectory), keep: 3)
        let day = Day(year: 2026, month: 10, day: 23)

        let copy = try #require(try backups.backUp(database, today: day))
        #expect(copy.lastPathComponent == "meals-2026-10-23.sqlite")
        // The same day again: nothing, unless asked.
        #expect(try backups.backUp(database, today: day) == nil)
        #expect(try backups.backUp(database, today: day, force: true) == copy)

        let restored = try DatabaseQueue(path: copy.path(percentEncoded: false))
        #expect(try restored.read { db in try String.fetchAll(db, sql: "SELECT name FROM category") } == ["Завтраки"])
        #expect(try restored.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM product") ?? 0 } > 300)

        for offset in 1...4 {
            try backups.backUp(database, today: day.adding(days: offset))
        }
        #expect(
            backups.copies().map(\.lastPathComponent) == [
                "meals-2026-10-27.sqlite", "meals-2026-10-26.sqlite", "meals-2026-10-25.sqlite",
            ])
    }
}
