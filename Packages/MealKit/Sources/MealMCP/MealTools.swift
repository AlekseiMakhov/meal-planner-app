import Foundation
import MCP
import MealCore
import MealStore

/// What Claude can ask Meal Planner & Recipes. For now only the server's status: recipes, products,
/// pantry, shopping and the week's menu arrive with their stages.
public struct MealTools: Sendable {
    let location: MealDataLocation
    let version: String

    public init(location: MealDataLocation, version: String) {
        self.location = location
        self.version = version
    }

    // MARK: - Definitions

    private static let readOnly = Tool.Annotations(readOnlyHint: true, openWorldHint: false)

    private static func schema(_ properties: [String: Value], required: [String] = []) -> Value {
        .object([
            "type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) }),
            "additionalProperties": false,
        ])
    }

    public static let all: [Tool] = [
        Tool(
            name: "get_status", title: "Состояние",
            description:
                "Версия сервера, папка с данными приложения и состояние базы: есть ли она и какие миграции схемы применены. Базу инструмент не создаёт.",
            inputSchema: schema([:]), annotations: readOnly)
    ]

    // MARK: - Calls

    public func call(_ name: String, arguments: [String: Value] = [:]) async -> CallTool.Result {
        do {
            let output: Value
            switch name {
            case "get_status": output = try status()
            default: throw ToolError("У сервера нет инструмента «\(name)».")
            }
            return CallTool.Result(content: [.text(text: ToolOutput.json(output), annotations: nil, _meta: nil)])
        } catch let error as ToolError {
            return CallTool.Result(content: [.text(text: error.message, annotations: nil, _meta: nil)], isError: true)
        } catch {
            return CallTool.Result(
                content: [.text(text: "Не получилось: \(error)", annotations: nil, _meta: nil)], isError: true)
        }
    }

    /// Reports the database without creating it: before the app's first launch there is none.
    private func status() throws -> Value {
        var database: [String: Value] = ["file": .string(location.databaseFile.path(percentEncoded: false))]
        if FileManager.default.fileExists(atPath: location.databaseFile.path(percentEncoded: false)) {
            let migrations = try AppDatabase.open(in: location.directory).appliedMigrations()
            database["exists"] = true
            database["migrations"] = .array(migrations.map { .string($0) })
        } else {
            database["exists"] = false
        }
        return .object([
            "app": .string(AppIdentity.displayName),
            "version": .string(version),
            "data_directory": .string(location.directory.path(percentEncoded: false)),
            "database": .object(database),
        ])
    }
}
