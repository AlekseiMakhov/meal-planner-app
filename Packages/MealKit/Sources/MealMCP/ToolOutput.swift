import Foundation
import MCP

/// A mistake in a call, told to Claude in words it can act on.
struct ToolError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// How tool results are written: JSON with snake_case keys.
enum ToolOutput {
    /// Pretty-printed JSON for the text content of a result.
    static func json(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}
