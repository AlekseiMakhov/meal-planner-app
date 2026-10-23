import LinkPresentation
import MealCore
import SwiftUI
import WebKit

/// A video player from YouTube, Rutube, VK or any iframe. The iframe sits in a page with an https address:
/// YouTube refuses to play («Ошибка 153») in a page without one, because no referrer reaches it.
struct VideoPlayerView: NSViewRepresentable {
    let player: VideoEmbed.Player

    /// The address the page claims; the player only needs one to send a referrer.
    private static let origin = URL(string: "https://mealplanner.inco.local/")!

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.underPageBackgroundColor = .black
        load(player.url, in: view, context: context)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.loaded != player.url {
            load(player.url, in: view, context: context)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var loaded: URL?
    }

    private func load(_ url: URL, in view: WKWebView, context: Context) {
        context.coordinator.loaded = url
        let source = url.absoluteString.replacingOccurrences(of: "\"", with: "%22")
        let html = """
            <!doctype html>
            <html><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
            iframe { border: 0; width: 100%; height: 100%; }</style></head>
            <body><iframe src="\(source)" referrerpolicy="strict-origin-when-cross-origin"
            allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe></body></html>
            """
        view.loadHTMLString(html, baseURL: Self.origin)
    }
}

/// A link as a card with the page's title and picture, as Messages shows it; a click opens the browser.
struct LinkPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LPLinkView {
        let view = LPLinkView(url: url)
        Task { @MainActor in
            if let metadata = await LinkMetadata.shared.metadata(for: url) {
                view.metadata = metadata
            }
        }
        return view
    }

    func updateNSView(_ view: LPLinkView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LPLinkView, context: Context) -> CGSize? {
        // The card sizes itself to its content; before the page's metadata arrives it has none yet.
        let width = min(proposal.width ?? 480, 560)
        let height = nsView.intrinsicContentSize.height
        return CGSize(width: width, height: height > 0 ? height : 72)
    }
}

/// Page titles and pictures, fetched once per link while the app runs.
@MainActor
final class LinkMetadata {
    static let shared = LinkMetadata()

    private var cache: [URL: LPLinkMetadata] = [:]

    func metadata(for url: URL) async -> LPLinkMetadata? {
        if let cached = cache[url] { return cached }
        let provider = LPMetadataProvider()
        provider.timeout = 15
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return nil }
        cache[url] = metadata
        return metadata
    }
}
