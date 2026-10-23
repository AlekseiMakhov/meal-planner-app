import MCP
import MealCore

/// The MCP server that Claude Desktop and Claude Code launch as `meal-planner-mcp`.
public enum MealMCPServer {
    public static let name = "meal-planner"

    /// Told to Claude when it connects: what the app is and the conventions its data follows.
    static let instructions = """
        Meal Planner & Recipes — личное приложение для Mac: рецепты с КБЖУ, база продуктов, запасы дома, список покупок \
        и меню на неделю. Сервер читает и пишет ту же базу, что и приложение; открытое приложение показывает изменения сразу.

        Правила:
        \(ClaudeRequest.rules)
        """

    public static func make(version: String, tools: MealTools) async -> Server {
        let server = Server(
            name: name,
            version: version,
            title: "Meal Planner & Recipes",
            instructions: instructions,
            capabilities: .init(prompts: .init(listChanged: false), tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: MealTools.all)
        }
        await server.withMethodHandler(CallTool.self) { params in
            await tools.call(params.name, arguments: params.arguments ?? [:])
        }
        await server.withMethodHandler(ListPrompts.self) { _ in
            ListPrompts.Result(prompts: MealPrompts.all)
        }
        await server.withMethodHandler(GetPrompt.self) { params in
            try MealPrompts.get(params.name, arguments: params.arguments ?? [:])
        }
        return server
    }

    /// Serves over stdin/stdout until the client disconnects; nothing else may write to stdout.
    public static func run(version: String, location: MealDataLocation) async throws {
        let server = await make(version: version, tools: MealTools(location: location, version: version))
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}
