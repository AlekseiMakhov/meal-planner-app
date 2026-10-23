import Foundation
import GRDB
import MealCore

/// The app's SQLite database. The app and its MCP server both read and write the same file through a
/// WAL `DatabasePool`; the busy timeout lets one wait out the other's transaction.
public struct AppDatabase: Sendable {
    public static let fileName = "meals.sqlite"

    let writer: any DatabaseWriter

    var reader: any DatabaseReader {
        writer
    }

    /// `~/Library/Application Support/inco.mealplanner`; a Debug build uses a folder of its own.
    public static func defaultDirectory(debug: Bool) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appending(path: AppIdentity.dataFolderName(debug: debug), directoryHint: .isDirectory)
    }

    public static func file(in directory: URL) -> URL {
        directory.appending(path: fileName)
    }

    /// Opens the database in the folder for reading and writing; creates the folder and the file, migrates
    /// the schema and loads the starting product base when needed.
    public static func open(in directory: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        let pool = try DatabasePool(path: file(in: directory).path(percentEncoded: false), configuration: configuration)
        return try AppDatabase(writer: pool, seeded: true)
    }

    /// A private database in memory, for tests and previews; empty unless asked for the starting base.
    public static func inMemory(seeded: Bool = false) throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue(), seeded: seeded)
    }

    private init(writer: any DatabaseWriter, seeded: Bool) throws {
        try Self.migrator(seeding: seeded).migrate(writer)
        self.writer = writer
    }

    /// The schema changes only through a new migration; migrations already applied are never edited. The
    /// starting base is a migration too, so it is loaded once and products deleted from it stay deleted.
    static func migrator(seeding: Bool) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("products") { db in
            try db.create(table: "aisle") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("seedKey", .text).unique()
            }
            try db.create(table: "product") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("nameKey", .text).notNull().unique()
                table.column("aliases", .text).notNull().defaults(to: "[]")
                table.column("aisleId", .integer).references("aisle", onDelete: .setNull)
                table.column("kcal", .double)
                table.column("protein", .double)
                table.column("fat", .double)
                table.column("carbs", .double)
                table.column("baseUnit", .text).notNull().defaults(to: BaseUnit.gram.rawValue)
                table.column("gramsPerPiece", .double)
                table.column("density", .double)
                table.column("namedUnits", .text).notNull().defaults(to: "{}")
                table.column("isStaple", .boolean).notNull().defaults(to: false)
                table.column("nutritionSource", .text)
                table.column("sourceNote", .text)
                table.column("needsReview", .boolean).notNull().defaults(to: false)
                table.column("seedKey", .text).unique()
                table.column("searchText", .text).notNull().defaults(to: "")
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "product_on_aisle", on: "product", columns: ["aisleId", "nameKey"])
            try db.create(index: "product_on_kcal", on: "product", columns: ["kcal"])
            try db.create(virtualTable: "product_ft", using: FTS5()) { table in
                table.synchronize(withTable: "product")
                table.tokenizer = .unicode61()
                table.column("searchText")
            }
        }
        if seeding {
            migrator.registerMigration("seed: products 1") { db in
                try SeedCatalog.insert(into: db)
            }
        }
        return migrator
    }

    /// The migrations applied to this database, in the order they were registered.
    public func appliedMigrations() throws -> [String] {
        try reader.read { db in try Self.migrator(seeding: true).appliedMigrations(db) }
    }

    /// "wal" for a file on disk; the app and the MCP server rely on it to work side by side.
    public func journalMode() throws -> String {
        try reader.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? "" }
    }
}

/// A refusal in words for the person: a name that is taken, a product that cannot be merged with itself.
public struct StoreError: Error, Hashable, Sendable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}
