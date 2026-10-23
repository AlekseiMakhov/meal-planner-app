import Foundation
import MCP
import MealStore
import Testing

@testable import MealMCP

/// The text of a successful result, read back as JSON.
func output(_ result: CallTool.Result) throws -> Value {
    #expect(result.isError != true, "\(result.content)")
    guard case .text(let text, _, _) = try #require(result.content.first) else {
        Issue.record("no text in the result")
        return .null
    }
    return try JSONDecoder().decode(Value.self, from: Data(text.utf8))
}

extension Value {
    subscript(_ key: String) -> Value? {
        objectValue?[key]
    }

    subscript(_ index: Int) -> Value? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }

    /// The `key` of every object in the array: the names of a list.
    func each(_ key: String) -> [String] {
        (arrayValue ?? []).compactMap { $0[key]?.stringValue }
    }
}

/// The server over a data folder of its own, with the app's database and the starting product base in it.
final class ToolFixture {
    let folder = FileManager.default.temporaryDirectory.appending(
        path: "meal mcp \(UUID().uuidString)", directoryHint: .isDirectory)
    let database: AppDatabase
    let tools: MealTools

    init() throws {
        database = try AppDatabase.open(in: folder)
        tools = MealTools(location: MealDataLocation(directory: folder), version: "test")
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The tool's JSON; an error result is recorded as an issue.
    func call(_ name: String, _ arguments: [String: Value] = [:]) async throws -> Value {
        try output(await tools.call(name, arguments: arguments))
    }

    /// The message of a call that has to fail.
    func failure(_ name: String, _ arguments: [String: Value] = [:]) async -> String {
        let result = await tools.call(name, arguments: arguments)
        #expect(result.isError == true, "\(result.content)")
        guard case .text(let text, _, _) = result.content.first else { return "" }
        return text
    }
}
