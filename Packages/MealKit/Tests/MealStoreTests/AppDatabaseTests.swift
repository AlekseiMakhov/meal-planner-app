import Foundation
import MealStore
import Testing

struct AppDatabaseTests {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "meal store \(UUID().uuidString)/data", directoryHint: .isDirectory)
    }

    @Test func openingCreatesTheFolderAndAWALDatabase() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let database = try AppDatabase.open(in: folder)
        #expect(FileManager.default.fileExists(atPath: AppDatabase.file(in: folder).path(percentEncoded: false)))
        #expect(try database.journalMode() == "wal")
        #expect(try database.appliedMigrations() == [])
    }

    @Test func secondConnectionOpensTheSameFile() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let app = try AppDatabase.open(in: folder)
        let server = try AppDatabase.open(in: folder)
        #expect(try app.appliedMigrations() == server.appliedMigrations())
    }

    @Test func inMemoryDatabaseIsMigrated() throws {
        #expect(try AppDatabase.inMemory().appliedMigrations() == [])
    }

    @Test func debugBuildUsesAFolderOfItsOwn() throws {
        let release = try AppDatabase.defaultDirectory(debug: false)
        let debug = try AppDatabase.defaultDirectory(debug: true)
        #expect(release.lastPathComponent == "inco.mealplanner")
        #expect(debug.lastPathComponent == "inco.mealplanner.debug")
        #expect(release.deletingLastPathComponent() == debug.deletingLastPathComponent())
    }
}
