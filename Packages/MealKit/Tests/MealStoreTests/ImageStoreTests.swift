import CoreGraphics
import Foundation
import ImageIO
import MealStore
import Testing
import UniformTypeIdentifiers

struct ImageStoreTests {
    /// A PNG of the given size, filled with one colour.
    static func png(width: Int, height: Int) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func store() -> ImageStore {
        ImageStore(
            directory: FileManager.default.temporaryDirectory.appending(
                path: "images \(UUID().uuidString)", directoryHint: .isDirectory))
    }

    private func size(_ url: URL) throws -> (Int, Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (
            properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        )
    }

    @Test func largeImagesShrinkTo1600PixelsAsJPEG() throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let name = try store.save(Self.png(width: 3200, height: 2000))
        #expect(name.hasSuffix(".jpg"))
        let (width, height) = try size(store.url(for: name))
        #expect(width == 1600)
        #expect(height == 1000)
    }

    @Test func smallImagesKeepTheirSize() throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let name = try store.save(Self.png(width: 300, height: 200))
        let (width, height) = try size(store.url(for: name))
        #expect(width == 300 && height == 200)
    }

    @Test func whatIsNotAnImageIsRefused() {
        #expect(throws: StoreError.self) { try store().save(Data("не картинка".utf8)) }
    }

    @Test func copiesAndDeletes() throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let name = try store.save(Self.png(width: 10, height: 10))
        let copy = try store.copy(name)
        #expect(copy != name)
        #expect(FileManager.default.fileExists(atPath: store.url(for: copy).path(percentEncoded: false)))
        store.delete(name)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: name).path(percentEncoded: false)))
    }

    @Test func unusedFilesGoOnlyWhenTheyAreOld() throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let kept = try store.save(Self.png(width: 10, height: 10))
        let fresh = try store.save(Self.png(width: 10, height: 10))
        let old = try store.save(Self.png(width: 10, height: 10))
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-7200)],
            ofItemAtPath: store.url(for: old).path(percentEncoded: false))
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-7200)],
            ofItemAtPath: store.url(for: kept).path(percentEncoded: false))
        #expect(store.removeUnused(keeping: [kept]) == 1)
        #expect(FileManager.default.fileExists(atPath: store.url(for: kept).path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: store.url(for: fresh).path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: store.url(for: old).path(percentEncoded: false)))
    }
}
