import Foundation
import GRDB
import MealCore

/// The app's SQLite database. The app and its MCP server both read and write the same file through a
/// WAL `DatabasePool`; the busy timeout lets one wait out the other's transaction.
public struct AppDatabase: Sendable {
    public static let fileName = "meals.sqlite"

    let writer: any DatabaseWriter
    /// Recipe photos: the «Images» folder next to the database file, or a temporary one for a database in memory.
    public let images: ImageStore

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
        return try AppDatabase(
            writer: pool,
            images: ImageStore(directory: directory.appending(path: "Images", directoryHint: .isDirectory)),
            seeded: true)
    }

    /// A private database in memory, for tests and previews; empty unless asked for the starting base.
    public static func inMemory(seeded: Bool = false) throws -> AppDatabase {
        let images = FileManager.default.temporaryDirectory.appending(
            path: "meal images \(UUID().uuidString)", directoryHint: .isDirectory)
        return try AppDatabase(writer: DatabaseQueue(), images: ImageStore(directory: images), seeded: seeded)
    }

    private init(writer: any DatabaseWriter, images: ImageStore, seeded: Bool) throws {
        try Self.migrator(seeding: seeded).migrate(writer)
        self.writer = writer
        self.images = images
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
        migrator.registerMigration("recipes") { db in
            try createRecipeTables(db)
        }
        migrator.registerMigration("pantry") { db in
            try createPantryTables(db)
        }
        return migrator
    }

    private static func createRecipeTables(_ db: Database) throws {
        try db.create(table: "category") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("name", .text).notNull()
            table.column("color", .text).notNull().defaults(to: TagColor.gray.rawValue)
            table.column("position", .integer).notNull()
        }
        try db.create(table: "meal_type") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("key", .text).unique()
            table.column("name", .text).notNull()
            table.column("color", .text).notNull()
            table.column("position", .integer).notNull()
        }
        let meals: [(String, String, TagColor)] = [
            ("breakfast", "Завтрак", .yellow), ("lunch", "Обед", .green), ("dinner", "Ужин", .blue),
            ("snack", "Перекус", .pink),
        ]
        for (position, (key, name, color)) in meals.enumerated() {
            try db.execute(
                sql: "INSERT INTO meal_type (key, name, color, position) VALUES (?, ?, ?, ?)",
                arguments: [key, name, color.rawValue, position])
        }
        try db.create(table: "recipe") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("title", .text).notNull()
            table.column("photo", .text)
            table.column("videoURL", .text)
            table.column("sourceURL", .text)
            table.column("servings", .integer).notNull().defaults(to: Recipe.defaultServings)
            table.column("yieldGrams", .double)
            table.column("prepMinutes", .integer)
            table.column("cookMinutes", .integer)
            table.column("notes", .text).notNull().defaults(to: "")
            table.column("overrideKcal", .double)
            table.column("overrideProtein", .double)
            table.column("overrideFat", .double)
            table.column("overrideCarbs", .double)
            table.column("isFavorite", .boolean).notNull().defaults(to: false)
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("deletedAt", .datetime)
        }
        try db.create(table: "recipe_category", options: .withoutRowID) { table in
            table.column("recipeId", .integer).notNull().references("recipe", onDelete: .cascade)
            table.column("categoryId", .integer).notNull().references("category", onDelete: .cascade)
            table.primaryKey(["recipeId", "categoryId"])
        }
        try db.create(index: "recipe_category_on_category", on: "recipe_category", columns: ["categoryId", "recipeId"])
        try db.create(table: "recipe_meal_type", options: .withoutRowID) { table in
            table.column("recipeId", .integer).notNull().references("recipe", onDelete: .cascade)
            table.column("mealTypeId", .integer).notNull().references("meal_type", onDelete: .cascade)
            table.primaryKey(["recipeId", "mealTypeId"])
        }
        try db.create(table: "recipe_ingredient") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("recipeId", .integer).notNull().references("recipe", onDelete: .cascade)
            // A product in a recipe cannot be deleted: it has to be taken out or merged first.
            table.column("productId", .integer).notNull().references("product", onDelete: .restrict)
            table.column("amount", .double)
            table.column("amountMax", .double)
            table.column("unit", .text)
            table.column("note", .text)
            table.column("groupName", .text)
            table.column("isOptional", .boolean).notNull().defaults(to: false)
            table.column("position", .integer).notNull()
        }
        try db.create(index: "recipe_ingredient_on_recipe", on: "recipe_ingredient", columns: ["recipeId", "position"])
        try db.create(
            index: "recipe_ingredient_on_product", on: "recipe_ingredient", columns: ["productId", "recipeId"])
        try db.create(table: "recipe_step") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("recipeId", .integer).notNull().references("recipe", onDelete: .cascade)
            table.column("position", .integer).notNull()
            table.column("text", .text).notNull()
        }
        try db.create(index: "recipe_step_on_recipe", on: "recipe_step", columns: ["recipeId", "position"])
        // What the lists sort and filter by, computed from the recipe and its products: see RecipeDerived.
        try db.create(table: "recipe_stats") { table in
            table.primaryKey("recipeId", .integer).references("recipe", onDelete: .cascade)
            table.column("titleKey", .text).notNull()
            table.column("searchText", .text).notNull()
            table.column("kcalPer100", .double)
            table.column("kcalPerServing", .double)
            table.column("proteinPerServing", .double)
            table.column("fatPerServing", .double)
            table.column("carbsPerServing", .double)
            table.column("totalMinutes", .integer)
            table.column("isNutritionComplete", .boolean).notNull()
        }
        try db.create(index: "recipe_stats_on_kcal", on: "recipe_stats", columns: ["kcalPerServing"])
        try db.create(virtualTable: "recipe_ft", using: FTS5()) { table in
            table.synchronize(withTable: "recipe_stats")
            table.tokenizer = .unicode61()
            table.column("searchText")
        }
    }

    private static func createPantryTables(_ db: Database) throws {
        // What there is at home, in the product's base unit: see PantryItem.
        try db.create(table: "pantry_item") { table in
            table.primaryKey("productId", .integer).references("product", onDelete: .cascade)
            table.column("quantity", .double)
            table.column("isLow", .boolean).notNull().defaults(to: false)
            table.column("updatedAt", .datetime).notNull()
        }
        try db.create(table: "shopping_item") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("productId", .integer).references("product", onDelete: .cascade)
            table.column("text", .text)
            // The text as names are compared: two «Батарейки» make one line.
            table.column("textKey", .text)
            table.column("amount", .double)
            table.column("unit", .text)
            table.column("reasons", .text).notNull().defaults(to: "[]")
            table.column("checkedAt", .datetime)
            table.column("stockedAt", .datetime)
            table.column("position", .integer).notNull()
            table.column("createdAt", .datetime).notNull()
        }
        try db.create(index: "shopping_item_on_product", on: "shopping_item", columns: ["productId"])
        try db.alter(table: "recipe_stats") { table in
            table.add(column: "missingCount", .integer).notNull().defaults(to: 0)
        }
        // With nothing at home yet, every line a recipe cannot do without is missing.
        try db.execute(
            sql: """
                UPDATE recipe_stats SET missingCount = (SELECT COUNT(*) FROM recipe_ingredient
                WHERE recipe_ingredient.recipeId = recipe_stats.recipeId AND NOT recipe_ingredient.isOptional)
                """)
        try db.create(index: "recipe_stats_on_missing", on: "recipe_stats", columns: ["missingCount"])
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
