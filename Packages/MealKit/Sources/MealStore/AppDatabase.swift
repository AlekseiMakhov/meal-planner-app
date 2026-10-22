import Foundation
import GRDB
import MealCore

/// The app's SQLite database. The app and its MCP server both read and write the same file through a
/// WAL `DatabasePool`; the busy timeout lets one wait out the other's transaction.
public struct AppDatabase: Sendable {
    public static let fileName = "meals.sqlite"

    let writer: any DatabaseWriter

    /// `~/Library/Application Support/inco.mealplanner`; a Debug build uses a folder of its own.
    public static func defaultDirectory(debug: Bool) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appending(path: AppIdentity.dataFolderName(debug: debug), directoryHint: .isDirectory)
    }

    public static func file(in directory: URL) -> URL {
        directory.appending(path: fileName)
    }

    /// Opens the database in the folder for reading and writing; creates the folder and the file and
    /// migrates the schema when needed.
    public static func open(in directory: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        return try AppDatabase(
            writer: DatabasePool(path: file(in: directory).path(percentEncoded: false), configuration: configuration))
    }

    /// A private database in memory, for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    private init(writer: any DatabaseWriter) throws {
        try Self.migrator.migrate(writer)
        self.writer = writer
    }

    /// The schema changes only through a new migration; migrations already applied are never edited.
    /// The first tables arrive in stage 1.
    static var migrator: DatabaseMigrator {
        DatabaseMigrator()
    }

    /// The migrations applied to this database, in the order they were registered.
    public func appliedMigrations() throws -> [String] {
        try writer.read { db in try Self.migrator.appliedMigrations(db) }
    }

    /// "wal" for a file on disk; the app and the MCP server rely on it to work side by side.
    public func journalMode() throws -> String {
        try writer.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? "" }
    }
}
