import Foundation
import MealStore
import Testing

struct AppDatabaseTests {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "meal store \(UUID().uuidString)/data", directoryHint: .isDirectory)
    }

    @Test func openingCreatesTheFolderAndAWALDatabaseWithTheStartingBase() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let database = try AppDatabase.open(in: folder)
        #expect(FileManager.default.fileExists(atPath: AppDatabase.file(in: folder).path(percentEncoded: false)))
        #expect(try database.journalMode() == "wal")
        #expect(
            try database.appliedMigrations() == [
                "products", "seed: products 1", "recipes", "pantry", "planner", "reminders", "pantry minimum",
            ])
    }

    @Test func secondConnectionOpensTheSameFile() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let app = try AppDatabase.open(in: folder)
        let server = try AppDatabase.open(in: folder)
        #expect(try app.appliedMigrations() == server.appliedMigrations())
        #expect(try app.products(.init(), limit: 1).total == server.products(.init(), limit: 1).total)
    }

    @Test func inMemoryDatabaseIsEmptyUnlessAskedForTheBase() throws {
        #expect(
            try AppDatabase.inMemory().appliedMigrations() == [
                "products", "recipes", "pantry", "planner", "reminders", "pantry minimum",
            ])
        #expect(try AppDatabase.inMemory().products(.init(), limit: 10).total == 0)
        #expect(try AppDatabase.inMemory(seeded: true).products(.init(), limit: 10).total > 300)
    }

    @Test func debugBuildUsesAFolderOfItsOwn() throws {
        let release = try AppDatabase.defaultDirectory(debug: false)
        let debug = try AppDatabase.defaultDirectory(debug: true)
        #expect(release.lastPathComponent == "inco.mealplanner")
        #expect(debug.lastPathComponent == "inco.mealplanner.debug")
        #expect(release.deletingLastPathComponent() == debug.deletingLastPathComponent())
    }

    @Test func theStartingBaseLoadsOnceAndDeletedProductsStayDeleted() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let database = try AppDatabase.open(in: folder)
        let total = try database.products(.init(), limit: 1).total
        let salt = try #require(try database.product(named: "Соль"))
        try database.deleteProduct(id: salt.id)

        let reopened = try AppDatabase.open(in: folder)
        #expect(try reopened.products(.init(), limit: 1).total == total - 1)
        #expect(try reopened.product(named: "Соль") == nil)
    }

    /// The MCP server writes through a connection of its own; the app's lists see it once told.
    @Test(.timeLimit(.minutes(1))) func aWriteFromAnotherConnectionReachesObservationsOnceNotified() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let app = try AppDatabase.open(in: folder)
        let server = try AppDatabase.open(in: folder)
        var categories = app.observeCategories().makeAsyncIterator()
        #expect(try await categories.next()?.isEmpty == true)
        _ = try server.newCategory(named: "Супы")
        try app.notifyExternalChanges()
        #expect(try await categories.next()?.map(\.category.name) == ["Супы"])
    }

    @Test func dataVersionChangesOnlyWhenAnotherConnectionWrites() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let app = try AppDatabase.open(in: folder)
        let server = try AppDatabase.open(in: folder)
        let before = try app.dataVersion()
        _ = try app.newCategory(named: "Завтраки")
        #expect(try app.dataVersion() == before)
        _ = try server.newCategory(named: "Супы")
        #expect(try app.dataVersion() != before)
    }
}
