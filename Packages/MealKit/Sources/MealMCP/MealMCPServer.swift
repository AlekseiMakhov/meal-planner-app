import MCP

/// The MCP server that Claude Desktop and Claude Code launch as `meal-planner-mcp`.
public enum MealMCPServer {
    public static let name = "meal-planner"

    /// Told to Claude when it connects: what the app is and what the server can do so far.
    static let instructions = """
        Meal Planner & Recipes — личное приложение для Mac: рецепты с КБЖУ, база продуктов, запасы дома, \
        список покупок и меню на неделю. Пока сервер умеет только сообщать о своём состоянии \
        (get_status); инструменты для рецептов, продуктов, запасов, покупок и меню появятся по мере \
        разработки.
        """

    public static func make(version: String, tools: MealTools) async -> Server {
        let server = Server(
            name: name,
            version: version,
            title: "Meal Planner & Recipes",
            instructions: instructions,
            capabilities: .init(tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: MealTools.all)
        }
        await server.withMethodHandler(CallTool.self) { params in
            await tools.call(params.name, arguments: params.arguments ?? [:])
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
