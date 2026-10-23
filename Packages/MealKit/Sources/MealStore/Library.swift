import Foundation
import GRDB
import MealCore

/// The recipe library a new installation starts from, the one an installer image carries: recipes with their
/// photos, categories, meals and products — without what belongs to one household.
extension AppDatabase {
    /// Writes the library into the folder, replacing what was there: the database without the pantry, the
    /// shopping list, the menu, the links with «Напоминания», the trash and empty drafts (no ingredients and no
    /// steps), its caches counted again for an empty pantry; and the photos its recipes use, in `Images`.
    public func exportLibrary(to folder: URL) throws {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appending(
            path: "meal library \(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }
        try copy(to: Self.file(in: work))

        let photos: [String]
        do {
            // The copy has this database's schema already: no migrations, no starting base loaded again.
            let library = try DatabaseQueue(path: Self.file(in: work).path(percentEncoded: false))
            photos = try library.write { db in
                try db.execute(
                    sql: """
                        DELETE FROM recipe WHERE deletedAt IS NOT NULL;
                        DELETE FROM recipe WHERE id NOT IN (SELECT recipeId FROM recipe_ingredient)
                            AND id NOT IN (SELECT recipeId FROM recipe_step);
                        DELETE FROM plan_entry;
                        DELETE FROM shopping_item;
                        DELETE FROM pantry_item;
                        DELETE FROM reminder_link;
                        DELETE FROM reminder_known;
                        """)
                try RecipeDerived.refresh(db, recipeIDs: Int64.fetchAll(db, sql: "SELECT id FROM recipe"))
                return try String.fetchAll(db, sql: "SELECT photo FROM recipe WHERE photo IS NOT NULL")
            }
            if fileManager.fileExists(atPath: folder.path(percentEncoded: false)) {
                try fileManager.removeItem(at: folder)
            }
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try library.writeWithoutTransaction { db in
                try db.execute(sql: "VACUUM INTO ?", arguments: [Self.file(in: folder).path(percentEncoded: false)])
            }
        }

        guard !photos.isEmpty else { return }
        let target = folder.appending(path: "Images", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        for photo in photos {
            // A photo that is gone from the disk leaves its recipe without a picture, as in the app.
            try? fileManager.copyItem(at: images.url(for: photo), to: target.appending(path: photo))
        }
    }

    /// A new data folder starts from the library: its photos, then its database, moved into place whole so that
    /// another process starting at the same moment never opens half a file. The first copy in place stands.
    static func installLibrary(from library: URL, into directory: URL) throws {
        let fileManager = FileManager.default
        let source = file(in: library)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { return }
        let photos = library.appending(path: "Images", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: photos.path(percentEncoded: false)) {
            let target = directory.appending(path: "Images", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            for name in try fileManager.contentsOfDirectory(atPath: photos.path(percentEncoded: false)) {
                try? fileManager.copyItem(at: photos.appending(path: name), to: target.appending(path: name))
            }
        }
        let destination = file(in: directory)
        let pending = directory.appending(path: "\(fileName).library-\(UUID().uuidString)")
        try fileManager.copyItem(at: source, to: pending)
        do {
            try fileManager.moveItem(at: pending, to: destination)
        } catch {
            try? fileManager.removeItem(at: pending)
            guard fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else { throw error }
        }
    }
}
