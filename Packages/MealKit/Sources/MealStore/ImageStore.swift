import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Recipe photos as files next to the database: each one shrunk to 1600 px on its longer side and saved as
/// JPEG under a name of its own. The database keeps only the name.
public struct ImageStore: Sendable {
    public let directory: URL

    public static let maxPixels = 1600
    /// Larger downloads are refused rather than read into memory.
    public static let maxDownloadBytes = 30 * 1024 * 1024

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(for name: String) -> URL {
        directory.appending(path: name)
    }

    /// Saves an image from its data: PNG, JPEG, HEIC, WebP — whatever ImageIO reads.
    public func save(_ data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw StoreError("Это не картинка или её формат не читается.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw StoreError("Картинку не получилось прочитать.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString.lowercased() + ".jpg"
        guard
            let destination = CGImageDestinationCreateWithURL(
                url(for: name) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw StoreError("Картинку не получилось сохранить.") }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StoreError("Картинку не получилось сохранить.") }
        return name
    }

    public func save(contentsOf file: URL) throws -> String {
        try save(Data(contentsOf: file))
    }

    /// Downloads an image from the web and saves it.
    public func download(_ url: URL) async throws -> String {
        guard url.scheme == "https" || url.scheme == "http" else { throw StoreError("Нужна ссылка на картинку.") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StoreError("Сайт не отдал картинку: ответ \(http.statusCode).")
        }
        guard data.count <= Self.maxDownloadBytes else { throw StoreError("Картинка больше 30 МБ.") }
        return try save(data)
    }

    /// A copy under a new name, for a recipe's duplicate: each recipe owns its photo.
    public func copy(_ name: String) throws -> String {
        let copy = UUID().uuidString.lowercased() + "." + (name.split(separator: ".").last.map(String.init) ?? "jpg")
        try FileManager.default.copyItem(at: url(for: name), to: url(for: copy))
        return copy
    }

    public func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    /// Removes files no recipe refers to: left behind by a crash between saving a photo and saving the recipe.
    /// Files changed in the last hour stay, in case a recipe is about to take them.
    @discardableResult
    public func removeUnused(keeping names: Set<String>) -> Int {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let hourAgo = Date.now.addingTimeInterval(-3600)
        var removed = 0
        for file in files where !names.contains(file.lastPathComponent) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard (modified ?? .distantPast) < hourAgo else { continue }
            if (try? FileManager.default.removeItem(at: file)) != nil { removed += 1 }
        }
        return removed
    }
}
