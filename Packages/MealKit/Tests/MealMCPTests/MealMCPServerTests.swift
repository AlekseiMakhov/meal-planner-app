import Foundation
import MCP
import MealStore
import Testing

@testable import MealMCP

/// The text of a successful result, read back as JSON.
private func output(_ result: CallTool.Result) throws -> Value {
    #expect(result.isError != true, "\(result.content)")
    guard case .text(let text, _, _) = try #require(result.content.first) else {
        Issue.record("no text in the result")
        return .null
    }
    return try JSONDecoder().decode(Value.self, from: Data(text.utf8))
}

extension Value {
    fileprivate subscript(_ key: String) -> Value? {
        objectValue?[key]
    }
}

struct MealMCPServerTests {
    private let folder = FileManager.default.temporaryDirectory.appending(
        path: "meal mcp \(UUID().uuidString)", directoryHint: .isDirectory)

    private var tools: MealTools {
        MealTools(location: MealDataLocation(directory: folder), version: "test")
    }

    @Test func handshakeIdentifiesServerAndListsTools() async throws {
        try await withConnectedClient(tools) { client, initialize in
            #expect(initialize.serverInfo.name == "meal-planner")
            #expect(initialize.serverInfo.version == "test")
            #expect(initialize.instructions?.contains("get_status") == true)
            let (tools, _) = try await client.listTools()
            #expect(tools.map(\.name) == ["get_status"])
            let result = try await client.callTool(name: "get_status")
            #expect(result.isError != true)
        }
    }

    @Test func statusBeforeTheAppEverRanDoesNotCreateTheDatabase() async throws {
        let status = try output(await tools.call("get_status"))
        #expect(status["app"]?.stringValue == "Meal Planner & Recipes")
        #expect(status["version"]?.stringValue == "test")
        #expect(status["data_directory"]?.stringValue == folder.path(percentEncoded: false))
        #expect(status["database"]?["exists"]?.boolValue == false)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test func statusReportsTheAppsDatabase() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try AppDatabase.open(in: folder)
        let status = try output(await tools.call("get_status"))
        #expect(status["database"]?["exists"]?.boolValue == true)
        #expect(status["database"]?["migrations"] == .array(["products", "seed: products 1"]))
    }

    @Test func unknownToolIsReportedAsToolError() async {
        let result = await tools.call("missing")
        #expect(result.isError == true)
    }

    @Test func aToolOutsideAnAppHasNoEnclosingApp() {
        #expect(MealDataLocation.enclosingApp(of: URL(filePath: "/usr/local/bin/meal-planner-mcp")) == nil)
    }

    private func withConnectedClient(
        _ tools: MealTools, _ body: (Client, Initialize.Result) async throws -> Void
    ) async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let server = await MealMCPServer.make(version: "test", tools: tools)
        try await server.start(transport: serverTransport)
        let client = Client(name: "tests", version: "1")
        let initialize = try await client.connect(transport: clientTransport)
        try await body(client, initialize)
        await client.disconnect()
        await server.stop()
    }
}
