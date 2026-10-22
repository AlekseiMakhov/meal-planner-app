import Foundation
import Testing

/// Runs inside MealPlanner.app (the test host), so Bundle.main is the built app.
struct PackagingTests {
    private let helper = Bundle.main.bundleURL.appending(path: "Contents/Helpers/meal-planner-mcp")

    @Test func peopleSeeTheFullName() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Meal Planner & Recipes")
        #expect(Bundle.main.bundleURL.lastPathComponent == "MealPlanner.app")
    }

    @Test func debugBuildHasAnIdentityOfItsOwn() {
        #expect(Bundle.main.bundleIdentifier == "inco.mealplanner.app.debug")
    }

    @Test func linksOpenTheApp() throws {
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes == ["mealplanner-debug"])
    }

    @Test func mcpServerIsEmbeddedAsHelper() {
        #expect(FileManager.default.isExecutableFile(atPath: helper.path(percentEncoded: false)))
    }

    /// The bundled server, started the way Claude Desktop starts it, answers over stdin and stdout.
    @Test func theBundledServerAnswersOverStdio() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "bundled server \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }

        let process = Process()
        process.executableURL = helper
        process.arguments = ["--directory", folder.path(percentEncoded: false)]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        defer { process.terminate() }
        var lines = output.fileHandleForReading.bytes.lines.makeAsyncIterator()
        func send(_ message: String) throws {
            try input.fileHandleForWriting.write(contentsOf: Data((message + "\n").utf8))
        }

        try send(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"tests","version":"1"}}}"#
        )
        let hello = try #require(try await lines.next())
        #expect(hello.contains(#""name":"meal-planner""#))
        try send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        try send(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = try #require(try await lines.next())
        #expect(tools.contains("get_status"))
        try send(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_status","arguments":{}}}"#)
        let status = try #require(try await lines.next())
        #expect(status.contains("Meal Planner & Recipes"))
        #expect(!status.contains(#""isError":true"#))
    }
}
