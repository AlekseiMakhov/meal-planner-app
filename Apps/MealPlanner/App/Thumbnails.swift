import AppKit
import ImageIO
import MealCore
import SwiftUI

/// Photos shrunk for cards and covers: decoded off the main thread and kept while memory allows.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()

    private let cache = NSCache<NSString, NSImage>()

    /// The image at most `pixels` on its longer side, or nil when the file is gone or unreadable.
    func image(at url: URL, pixels: Int) async -> NSImage? {
        let key = "\(url.path(percentEncoded: false))#\(pixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let decoded = await Task.detached(priority: .userInitiated) { Self.decode(url, pixels: pixels) }.value
        guard let decoded else { return nil }
        let image = NSImage(
            cgImage: decoded.image, size: NSSize(width: decoded.image.width, height: decoded.image.height))
        cache.setObject(image, forKey: key)
        return image
    }

    /// A CGImage handed from the decoding task to the main actor; nothing else holds it.
    private struct Decoded: @unchecked Sendable {
        let image: CGImage
    }

    nonisolated private static func decode(_ url: URL, pixels: Int) -> Decoded? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(Decoded.init)
    }
}

extension TagColor {
    var color: Color {
        switch self {
        case .gray: Color(.tagGray)
        case .brown: Color(.tagBrown)
        case .orange: Color(.tagOrange)
        case .yellow: Color(.tagYellow)
        case .green: Color(.tagGreen)
        case .blue: Color(.tagBlue)
        case .purple: Color(.tagPurple)
        case .pink: Color(.tagPink)
        case .red: Color(.tagRed)
        }
    }
}

/// A tag as Notion draws it: the name on a muted colour.
struct TagView: View {
    let name: String
    let color: TagColor
    var isOn = true

    var body: some View {
        Text(name)
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(isOn ? color.color : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isOn ? Color.clear : Color(.hairline)))
            .foregroundStyle(isOn ? Color(.textPrimary) : Color(.textSecondary))
    }
}
