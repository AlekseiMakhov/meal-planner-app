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
        #expect(try database.appliedMigrations() == ["products", "seed: products 1"])
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
        #expect(try AppDatabase.inMemory().appliedMigrations() == ["products"])
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
}
