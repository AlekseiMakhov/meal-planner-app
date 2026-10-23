import Foundation
import GRDB
import MealCore

/// Copies of the database, one a day: `meals-2026-10-23.sqlite` in a folder of its own, the newest 14 kept. A copy
/// is the whole database at one moment, written by `VACUUM INTO` while the app works on; photos stay in their
/// folder and are not copied.
public struct Backups: Sendable {
    public let folder: URL
    public let keep: Int

    public init(folder: URL, keep: Int = 14) {
        self.folder = folder
        self.keep = keep
    }

    /// The copies there are, the newest first.
    public func copies() -> [URL] {
        let files =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("meals-") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    public func file(for day: Day) -> URL {
        folder.appending(path: "meals-\(day).sqlite")
    }

    /// Today's copy unless there is one already; the oldest beyond `keep` go. Returns the new copy, if one was made.
    @discardableResult
    public func backUp(_ database: AppDatabase, today: Day = .today(), force: Bool = false) throws -> URL? {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = file(for: today)
        let exists = FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
        if exists, !force {
            return nil
        }
        if exists {
            try FileManager.default.removeItem(at: file)
        }
        try database.copy(to: file)
        for old in copies().dropFirst(keep) {
            try? FileManager.default.removeItem(at: old)
        }
        return file
    }
}

extension AppDatabase {
    /// The whole database into a new file at one moment, compacted: `VACUUM INTO`.
    public func copy(to file: URL) throws {
        try writer.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [file.path(percentEncoded: false)])
        }
    }
}
