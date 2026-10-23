import Foundation

/// A recipe as a web page describes it for search engines: schema.org/Recipe in JSON-LD, which most recipe sites
/// put into their HTML.
public struct ImportedRecipe: Hashable, Sendable {
    public var title: String
    public var description: String?
    public var imageURL: URL?
    public var servings: Int?
    public var prepMinutes: Int?
    public var cookMinutes: Int?
    public var totalMinutes: Int?
    /// The ingredient lines as written: «40 г феты».
    public var ingredients: [String]
    public var steps: [String]
    public var videoURL: String?
    public var sourceURL: String?

    public init(
        title: String, description: String? = nil, imageURL: URL? = nil, servings: Int? = nil, prepMinutes: Int? = nil,
        cookMinutes: Int? = nil, totalMinutes: Int? = nil, ingredients: [String] = [], steps: [String] = [],
        videoURL: String? = nil, sourceURL: String? = nil
    ) {
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.totalMinutes = totalMinutes
        self.ingredients = ingredients
        self.steps = steps
        self.videoURL = videoURL
        self.sourceURL = sourceURL
    }
}

/// Reads schema.org/Recipe out of a page's `<script type="application/ld+json">` blocks: a recipe on its own, in
/// an array, or in a `@graph`; steps as text, `HowToStep` or `HowToSection`; durations as ISO 8601 («PT1H30M»).
public enum RecipeImport {
    /// The page's recipe; nil when the page has none.
    public static func recipe(inHTML html: String, url: URL? = nil) -> ImportedRecipe? {
        for block in jsonBlocks(in: html) {
            guard let object = findRecipe(in: block) else { continue }
            let title = clean(string(object["name"]) ?? "")
            guard !title.isEmpty else { continue }
            var recipe = ImportedRecipe(title: title)
            recipe.description = string(object["description"]).map(clean).flatMap { $0.isEmpty ? nil : $0 }
            recipe.imageURL = image(object["image"], base: url)
            recipe.servings = servings(object["recipeYield"])
            recipe.prepMinutes = minutes(string(object["prepTime"]))
            recipe.cookMinutes = minutes(string(object["cookTime"]))
            recipe.totalMinutes = minutes(string(object["totalTime"]))
            recipe.ingredients = strings(object["recipeIngredient"] ?? object["ingredients"]).map(clean)
                .filter { !$0.isEmpty }
            recipe.steps = steps(object["recipeInstructions"])
            recipe.videoURL = video(object["video"])
            recipe.sourceURL = url?.absoluteString ?? string(object["url"])
            return recipe
        }
        return nil
    }

    // MARK: - Finding the recipe

    static func jsonBlocks(in html: String) -> [Any] {
        let pattern = #"<script[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>(.*?)</script>"#
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let body = Range(match.range(at: 1), in: html) else { return nil }
            var text = String(html[body]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Some sites wrap the JSON in an HTML comment or CDATA.
            for wrapper in ["<!--", "-->", "<![CDATA[", "]]>"] {
                text = text.replacingOccurrences(of: wrapper, with: "")
            }
            return try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        }
    }

    static func findRecipe(in json: Any) -> [String: Any]? {
        if let array = json as? [Any] {
            return array.lazy.compactMap(findRecipe).first
        }
        guard let object = json as? [String: Any] else { return nil }
        if isRecipe(object["@type"]) {
            return object
        }
        if let graph = object["@graph"], let found = findRecipe(in: graph) {
            return found
        }
        if let main = object["mainEntity"], let found = findRecipe(in: main) {
            return found
        }
        return nil
    }

    private static func isRecipe(_ type: Any?) -> Bool {
        if let type = type as? String { return type.hasSuffix("Recipe") }
        if let types = type as? [Any] { return types.contains { isRecipe($0) } }
        return false
    }

    // MARK: - Values

    static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        case let array as [Any]: array.lazy.compactMap(string).first
        case let object as [String: Any]: string(object["text"] ?? object["name"] ?? object["@value"])
        default: nil
        }
    }

    static func strings(_ value: Any?) -> [String] {
        switch value {
        case let text as String: text.components(separatedBy: .newlines)
        case let array as [Any]: array.compactMap(string)
        default: []
        }
    }

    /// «PT1H30M» → 90; «P0DT0H20M» → 20; «PT45S» → 1.
    static func minutes(_ text: String?) -> Int? {
        guard let text = text?.uppercased(), text.hasPrefix("P") else { return nil }
        var total = 0.0
        var number = ""
        var inTime = false
        for character in text.dropFirst() {
            if character == "T" {
                inTime = true
            } else if character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
            } else {
                let value = Double(number) ?? 0
                number = ""
                switch (character, inTime) {
                case ("D", _): total += value * 24 * 60
                case ("H", true): total += value * 60
                case ("M", true): total += value
                case ("S", true): total += value / 60
                default: break
                }
            }
        }
        guard total > 0 else { return nil }
        return Int(total.rounded(.up))
    }

    /// «4», 4, «4 порции», «Serves 4», ["4", "4 servings"]: the first whole number.
    static func servings(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue > 0 ? number.intValue : nil
        }
        if let array = value as? [Any] {
            return array.lazy.compactMap(servings).first
        }
        guard let text = value as? String else { return nil }
        let digits = text.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
        return digits.flatMap { (1...100).contains($0) ? $0 : nil }
    }

    static func image(_ value: Any?, base: URL?) -> URL? {
        let text: String? =
            switch value {
            case let text as String: text
            case let array as [Any]: array.lazy.compactMap { image($0, base: base)?.absoluteString }.first
            case let object as [String: Any]: (object["url"] ?? object["contentUrl"]) as? String
            default: nil
            }
        guard let text, let url = URL(string: text, relativeTo: base)?.absoluteURL,
            ["http", "https"].contains(url.scheme ?? "")
        else { return nil }
        return url
    }

    /// Steps as text: one per `HowToStep`, sections flattened in order, a block of text split into its lines.
    static func steps(_ value: Any?) -> [String] {
        var result: [String] = []
        func walk(_ value: Any?) {
            switch value {
            case let text as String:
                result += clean(text).components(separatedBy: .newlines)
            case let array as [Any]:
                array.forEach(walk)
            case let object as [String: Any]:
                if let items = object["itemListElement"] {
                    walk(items)
                } else if let text = object["text"] ?? object["name"] {
                    walk(text)
                }
            default:
                break
            }
        }
        walk(value)
        return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func video(_ value: Any?) -> String? {
        if let array = value as? [Any] {
            return array.lazy.compactMap(video).first
        }
        guard let object = value as? [String: Any] else { return value as? String }
        return (object["embedUrl"] ?? object["contentUrl"] ?? object["url"]) as? String
    }

    /// Text without tags and HTML entities, spaces tidied: what sites leave in their JSON-LD.
    static func clean(_ text: String) -> String {
        var text = text.replacingOccurrences(
            of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
            "&laquo;": "«", "&raquo;": "»", "&ndash;": "–", "&mdash;": "—", "&frac12;": "½", "&frac14;": "¼",
            "&frac34;": "¾", "&deg;": "°",
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let range = NSRange(text.startIndex..., in: text)
            var decoded = text
            for match in regex.matches(in: text, range: range).reversed() {
                guard let whole = Range(match.range, in: decoded), let digits = Range(match.range(at: 2), in: text),
                    let hex = Range(match.range(at: 1), in: text)
                else { continue }
                let radix = text[hex].isEmpty ? 10 : 16
                if let code = UInt32(text[digits], radix: radix), let scalar = Unicode.Scalar(code) {
                    decoded.replaceSubrange(whole, with: String(Character(scalar)))
                }
            }
            text = decoded
        }
        return text.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
