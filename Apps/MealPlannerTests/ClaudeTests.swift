import Foundation
import MealCore
import MealStore
import Testing

@testable import MealPlanner

struct ClaudeConnectionTests {
    private let folder = FileManager.default.temporaryDirectory.appending(
        path: "claude config \(UUID().uuidString)", directoryHint: .isDirectory)

    private func connection(command: String = "/Applications/MealPlanner.app/Contents/Helpers/meal-planner-mcp")
        -> ClaudeConnection
    {
        ClaudeConnection(
            serverName: "meal-planner", command: command, config: folder.appending(path: "claude_desktop_config.json"))
    }

    private func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: connection().config)
    }

    private func config() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: connection().config)) as? [String: Any])
    }

    @Test func installingAddsOurServerAndKeepsTheRest() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = #"{"preferences": {"theme": "dark"}, "mcpServers": {"other": {"command": "/bin/other"}}}"#
        try write(original)
        #expect(connection().state() == .missing)

        let backup = try #require(try connection().install(now: Date(timeIntervalSince1970: 1_792_670_400)))
        #expect(connection().state() == .connected)
        let object = try config()
        let servers = try #require(object["mcpServers"] as? [String: Any])
        #expect(Set(servers.keys) == ["other", "meal-planner"])
        #expect((servers["meal-planner"] as? [String: Any])?["command"] as? String == connection().command)
        #expect((object["preferences"] as? [String: Any])?["theme"] as? String == "dark")
        #expect(String(decoding: try Data(contentsOf: backup), as: UTF8.self) == original)
        #expect(backup.lastPathComponent.hasPrefix("claude_desktop_config.json.backup-2026-10-22"))
    }

    @Test func aMissingConfigIsCreated() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(connection().state() == .missing)
        #expect(try connection().install() == nil)
        #expect(connection().state() == .connected)
    }

    @Test func anotherCopyOfTheAppIsNamedAndReplaced() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try connection(command: "/old/MealPlanner.app/Contents/Helpers/meal-planner-mcp").install()
        #expect(connection().state() == .otherCopy("/old/MealPlanner.app/Contents/Helpers/meal-planner-mcp"))
        try connection().install()
        #expect(connection().state() == .connected)
    }

    @Test func removingLeavesOtherServers() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(#"{"mcpServers": {"other": {"command": "/bin/other"}}}"#)
        try connection().install()
        try connection().remove()
        #expect(connection().state() == .missing)
        #expect((try config()["mcpServers"] as? [String: Any])?.keys.sorted() == ["other"])
        #expect(try connection().remove() == nil)
    }

    @Test func aBrokenConfigIsLeftAlone() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("{ not json")
        guard case .unreadable = connection().state() else {
            Issue.record("a broken config should read as unreadable")
            return
        }
        #expect(throws: (any Error).self) { try connection().install() }
        #expect(String(decoding: try Data(contentsOf: connection().config), as: UTF8.self) == "{ not json")
    }

    @Test func theSnippetIsTheEntryToPaste() throws {
        let snippet = connection().snippet
        let object = try #require(try JSONSerialization.jsonObject(with: Data(snippet.utf8)) as? [String: Any])
        let servers = try #require(object["mcpServers"] as? [String: Any])
        #expect((servers["meal-planner"] as? [String: Any])?["command"] as? String == connection().command)
    }

    @Test func theTerminalCommandQuotesAPathWithSpacesAndAmpersand() {
        let command = connection(command: "/Users/me/Meal Planner & Recipes App/build/MealPlanner.app/x").cliCommand
        #expect(
            command
                == "claude mcp add --scope user meal-planner -- '/Users/me/Meal Planner & Recipes App/build/MealPlanner.app/x'"
        )
    }

    @Test func debugBuildConnectsUnderANameOfItsOwn() {
        #expect(ClaudeConnection.current.serverName == "meal-planner-debug")
        #expect(ClaudeConnection.current.command.hasSuffix("MealPlanner.app/Contents/Helpers/meal-planner-mcp"))
    }
}

struct ClaudeLinkTests {
    @Test func theCodeSessionGetsTheFolderAndTheRequestIntact() throws {
        let request = "Добавь рецепт: https://example.com/a?b=1&c=2 + «соус» #1\n100% ok?"
        let folder = URL(
            filePath: "/Users/me/Library/Application Support/inco.mealplanner/Meal Planner", directoryHint: .isDirectory
        )
        let link = try #require(ClaudeHandoff.codeSession(request, folder: folder))
        #expect(link.scheme == "claude")
        #expect(link.host == "code")
        #expect(link.path == "/new")
        // «+» must stay «+», not become a space, as URLSearchParams would read a bare one.
        #expect(!link.absoluteString.contains("+"))
        let query = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.map(\.name) == ["folder", "q"])
        #expect(query.first?.value == "/Users/me/Library/Application Support/inco.mealplanner/Meal Planner")
        #expect(query.last?.value == request)
    }

    @Test func aCodeSessionFilesItselfAtTheEnd() {
        let request = ClaudeHandoff.forCodeSession("Добавь рецепт")
        #expect(request.hasPrefix("Добавь рецепт"))
        #expect(request.contains("«Meal Planner»"))
    }

    @Test func theImportSheetTakesWebLinksOnly() {
        #expect(ClaudeImportSheet.webLink("https://povar.ru/recipes/omlet-1.html")?.host() == "povar.ru")
        #expect(ClaudeImportSheet.webLink("  youtu.be/abc  ")?.absoluteString == "https://youtu.be/abc")
        #expect(ClaudeImportSheet.webLink("омлет с фетой") == nil)
        #expect(ClaudeImportSheet.webLink("file:///etc/hosts") == nil)
        #expect(ClaudeImportSheet.webLink("localhost") == nil)
    }
}

struct ClaudeWorkspaceTests {
    @Test func theFolderGetsTheInstructionsAndKeepsTheUsersOwn() throws {
        let data = FileManager.default.temporaryDirectory.appending(
            path: "claude workspace \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: data) }
        let workspace = ClaudeWorkspace(dataDirectory: data)
        #expect(workspace.folder.lastPathComponent == "Meal Planner")
        try workspace.prepare()
        let instructions = try String(contentsOf: workspace.instructionsFile, encoding: .utf8)
        #expect(instructions.contains("create_recipe"))
        #expect(instructions.contains("именительном падеже"))
        #expect(instructions.contains("USDA"))
        // A settings file would make Claude Desktop ask to trust the folder on every link from the app.
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: workspace.folder.path(percentEncoded: false))
                == ["CLAUDE.md"])

        try Data("Свои указания".utf8).write(to: workspace.instructionsFile)
        try workspace.prepare()
        #expect(try String(contentsOf: workspace.instructionsFile, encoding: .utf8) == "Свои указания")

        let earlier: Set = [ClaudeWorkspace.digest(Data("Свои указания".utf8))]
        try workspace.prepare(replacing: earlier)
        #expect(try String(contentsOf: workspace.instructionsFile, encoding: .utf8) == ClaudeWorkspace.instructions)
    }

    @Test func requestsNameTheirToolsAndWhatTheyWorkOn() {
        #expect(ClaudeRequest.importRecipe(url: "https://example.com/r", category: "Супы").contains("«Супы»"))
        #expect(ClaudeRequest.importRecipe(url: "https://example.com/r", category: nil).contains("list_categories"))
        #expect(ClaudeRequest.fillRecipe("«Омлет» (id 12)").contains("«Омлет» (id 12)"))
        #expect(ClaudeRequest.fillNutrition(nil).contains("\"missing\""))
        #expect(ClaudeRequest.fillNutrition("«Фета»").contains("«Фета»"))
        #expect(ClaudeRequest.migrateFromNotion("Recipes").contains("create_recipe"))
    }
}

/// The open app's lists follow what the MCP server writes from its own process.
@MainActor
struct ExternalChangesTests {
    @Test(.timeLimit(.minutes(1))) func aDarwinNotificationReachesTheObserver() async throws {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let observer = ExternalChangesObserver { continuation.yield() }
        ExternalChanges.post()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        withExtendedLifetime(observer) {}
    }
}
