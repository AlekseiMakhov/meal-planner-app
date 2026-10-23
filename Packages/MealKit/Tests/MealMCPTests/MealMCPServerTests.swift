import Foundation
import MCP
import MealStore
import Testing

@testable import MealMCP

struct MealMCPServerTests {
    private let folder = FileManager.default.temporaryDirectory.appending(
        path: "meal mcp \(UUID().uuidString)", directoryHint: .isDirectory)

    private var tools: MealTools {
        MealTools(location: MealDataLocation(directory: folder), version: "test")
    }

    @Test func handshakeIdentifiesServerAndListsToolsAndPrompts() async throws {
        try await withConnectedClient(tools) { client, initialize in
            #expect(initialize.serverInfo.name == "meal-planner")
            #expect(initialize.serverInfo.version == "test")
            #expect(initialize.instructions?.contains("search_products") == true)
            let (tools, _) = try await client.listTools()
            #expect(tools.map(\.name) == MealTools.all.map(\.name))
            let result = try await client.callTool(name: "get_status")
            #expect(result.isError != true)

            let (prompts, _) = try await client.listPrompts()
            #expect(
                prompts.map(\.name) == [
                    "import_recipe", "fill_recipe", "fill_nutrition", "what_to_cook", "plan_week",
                    "migrate_from_notion",
                ])
            let prompt = try await client.getPrompt(
                name: "import_recipe", arguments: ["url": "https://example.com/omelette", "category": "Завтраки"])
            guard case .text(let text) = try #require(prompt.messages.first).content else {
                Issue.record("no text in the prompt")
                return
            }
            #expect(text.contains("https://example.com/omelette"))
            #expect(text.contains("«Завтраки»"))
        }
    }

    @Test func everyListedToolIsServedAndNamedOnce() async {
        let names = MealTools.all.map(\.name)
        #expect(Set(names).count == names.count)
        for name in names {
            let result = await tools.call(name)
            guard case .text(let text, _, _) = result.content.first else { continue }
            #expect(!text.contains("нет инструмента"), "\(name)")
        }
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func promptsAskForWhatTheyNeed() throws {
        #expect(throws: MCPError.self) { try MealPrompts.get("import_recipe") }
        #expect(throws: MCPError.self) { try MealPrompts.get("missing") }
        let migrate = try MealPrompts.get("migrate_from_notion")
        guard case .text(let text) = try #require(migrate.messages.first).content else {
            Issue.record("no text in the prompt")
            return
        }
        #expect(text.contains("Recipes"))
        #expect(text.contains("create_recipe"))
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
        #expect(
            status["database"]?["migrations"]
                == .array(["products", "seed: products 1", "recipes", "pantry", "planner", "reminders"]))
        #expect((status["database"]?["products"]?.intValue ?? 0) > 300)
        #expect(status["database"]?["recipes"]?.intValue == 0)
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
