import Foundation

/// Turns a video link, or the `<iframe>` code a site offers for embedding, into a player the recipe page can
/// show: YouTube, Rutube, VK Video, or any iframe's own address.
public enum VideoEmbed {
    public enum Provider: String, Hashable, Sendable {
        case youtube, rutube, vk, iframe

        public var title: String {
            switch self {
            case .youtube: "YouTube"
            case .rutube: "Rutube"
            case .vk: "VK Видео"
            case .iframe: "Видео"
            }
        }
    }

    public struct Player: Hashable, Sendable {
        public let provider: Provider
        public let url: URL
        /// The page to open in a browser when the player does not start.
        public let page: URL
    }

    /// The player for the text, or nil when it is neither a known video page nor an iframe.
    public static func player(for text: String) -> Player? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().contains("<iframe") {
            guard let source = iframeSource(text), let url = URL(string: source), url.scheme?.hasPrefix("http") == true
            else { return nil }
            return player(for: url) ?? Player(provider: .iframe, url: url, page: url)
        }
        guard let url = URL(string: text), url.scheme?.hasPrefix("http") == true else { return nil }
        return player(for: url)
    }

    private static func player(for url: URL) -> Player? {
        guard let host = url.host()?.lowercased() else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(
            (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        let path = url.path().split(separator: "/").map(String.init)

        if host == "youtu.be" || host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            let id: String? =
                host == "youtu.be"
                ? path.first
                : ["shorts", "embed", "live", "v"].contains(path.first ?? "") && path.count > 1 ? path[1] : query["v"]
            guard let id, isVideoID(id) else { return nil }
            var player = URLComponents(string: "https://www.youtube-nocookie.com/embed/\(id)")!
            var items = [URLQueryItem(name: "rel", value: "0")]
            if let start = seconds(query["t"] ?? query["start"]) {
                items.append(URLQueryItem(name: "start", value: String(start)))
            }
            player.queryItems = items
            return Player(
                provider: .youtube, url: player.url!, page: URL(string: "https://www.youtube.com/watch?v=\(id)")!)
        }
        if host.hasSuffix("rutube.ru") {
            let markers = ["video", "shorts", "embed"]
            guard let index = path.firstIndex(where: markers.contains), path.count > index + 1 else { return nil }
            let id = path[index + 1]
            guard isVideoID(id) else { return nil }
            return Player(
                provider: .rutube, url: URL(string: "https://rutube.ru/play/embed/\(id)")!,
                page: URL(string: "https://rutube.ru/video/\(id)/")!)
        }
        if host.hasSuffix("vk.com") || host.hasSuffix("vkvideo.ru") || host.hasSuffix("vk.ru") {
            if path.first == "video_ext.php", let owner = query["oid"], let id = query["id"] {
                return vkPlayer(owner: owner, id: id, hash: query["hash"])
            }
            // vk.com/video-123_456, vk.com/clip-123_456, vk.com/club1?z=video-123_456
            let candidates = path + [query["z"] ?? ""]
            for candidate in candidates {
                guard
                    let match = candidate.firstMatch(of: /(?:video|clip)(-?\d+)_(\d+)/)
                else { continue }
                return vkPlayer(owner: String(match.output.1), id: String(match.output.2), hash: nil)
            }
            return nil
        }
        return nil
    }

    private static func vkPlayer(owner: String, id: String, hash: String?) -> Player? {
        guard Int(owner) != nil, Int(id) != nil else { return nil }
        var player = URLComponents(string: "https://vkvideo.ru/video_ext.php")!
        player.queryItems =
            [URLQueryItem(name: "oid", value: owner), URLQueryItem(name: "id", value: id)]
            + (hash.map { [URLQueryItem(name: "hash", value: $0)] } ?? []) + [URLQueryItem(name: "hd", value: "2")]
        return Player(provider: .vk, url: player.url!, page: URL(string: "https://vkvideo.ru/video\(owner)_\(id)")!)
    }

    private static func iframeSource(_ code: String) -> String? {
        guard let match = code.firstMatch(of: /src\s*=\s*["']([^"']+)["']/.ignoresCase()) else { return nil }
        return String(match.output.1).replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func isVideoID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// «90», «90s», «1m30s», «1h2m3s» as seconds.
    private static func seconds(_ text: String?) -> Int? {
        guard let text, !text.isEmpty else { return nil }
        if let plain = Int(text) { return plain }
        var total = 0
        var number = ""
        for character in text {
            if character.isNumber {
                number.append(character)
            } else {
                guard let value = Int(number) else { return nil }
                switch character {
                case "h": total += value * 3600
                case "m": total += value * 60
                case "s": total += value
                default: return nil
                }
                number = ""
            }
        }
        return number.isEmpty ? total : nil
    }
}
