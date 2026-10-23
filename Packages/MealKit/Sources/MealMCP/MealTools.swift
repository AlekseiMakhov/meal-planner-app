import Foundation
import MCP
import MealCore
import MealStore

/// What Claude can do with Meal Planner & Recipes: read and change products, categories and recipes. The
/// server writes to the same database as the app; after every change it tells the app to refresh.
public struct MealTools: Sendable {
    let location: MealDataLocation
    let version: String

    public init(location: MealDataLocation, version: String) {
        self.location = location
        self.version = version
    }

    func database() throws -> AppDatabase {
        try AppDatabase.open(in: location.directory)
    }

    // MARK: - Definitions

    static let readOnly = Tool.Annotations(readOnlyHint: true, openWorldHint: false)
    static let changes = Tool.Annotations(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
    static let idempotent = Tool.Annotations(
        readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
    static let destructive = Tool.Annotations(readOnlyHint: false, destructiveHint: true, openWorldHint: false)

    static func schema(_ properties: [String: Value], required: [String] = []) -> Value {
        .object([
            "type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) }),
            "additionalProperties": false,
        ])
    }

    static func string(_ description: String) -> Value {
        .object(["type": "string", "description": .string(description)])
    }

    static func integer(_ description: String) -> Value {
        .object(["type": "integer", "description": .string(description)])
    }

    static func number(_ description: String) -> Value {
        .object(["type": "number", "description": .string(description)])
    }

    static func boolean(_ description: String) -> Value {
        .object(["type": "boolean", "description": .string(description)])
    }

    static func strings(_ description: String) -> Value {
        .object(["type": "array", "items": ["type": "string"], "description": .string(description)])
    }

    static func choice(_ values: [String], _ description: String) -> Value {
        .object(["type": "string", "enum": .array(values.map(Value.string)), "description": .string(description)])
    }

    static let page: [String: Value] = [
        "limit": integer("Сколько вернуть, 1–100; по умолчанию 30."),
        "cursor": string("next_cursor из прошлого ответа, чтобы получить следующую страницу."),
        "descending": boolean("Обратный порядок сортировки."),
    ]

    public static let all: [Tool] =
        [
            Tool(
                name: "get_status", title: "Состояние",
                description:
                    "Версия сервера, папка с данными, состояние базы и сколько в ней продуктов, рецептов и категорий. Базу инструмент не создаёт.",
                inputSchema: schema([:]), annotations: readOnly),
            Tool(
                name: "list_aisles", title: "Отделы магазина",
                description:
                    "Отделы магазина по порядку: «Овощи и зелень», «Молочное и яйца»… Нужны, чтобы указать отдел продукта в upsert_product.",
                inputSchema: schema([:]), annotations: readOnly),
        ] + productTools + categoryTools + recipeTools

    // MARK: - Calls

    public func call(_ name: String, arguments: [String: Value] = [:]) async -> CallTool.Result {
        let arguments = Arguments(arguments)
        do {
            let output: Value
            var changed = true
            switch name {
            case "get_status":
                output = try status()
                changed = false
            case "list_aisles":
                output = try listAisles()
                changed = false
            case "search_products":
                output = try searchProducts(arguments)
                changed = false
            case "get_product":
                output = try getProduct(arguments)
                changed = false
            case "upsert_product": output = try upsertProduct(arguments)
            case "merge_products": output = try mergeProducts(arguments)
            case "list_categories":
                output = try listCategories()
                changed = false
            case "create_category": output = try createCategory(arguments)
            case "update_category": output = try updateCategory(arguments)
            case "delete_category": output = try deleteCategory(arguments)
            case "search_recipes":
                output = try searchRecipes(arguments)
                changed = false
            case "get_recipe":
                output = try getRecipe(arguments)
                changed = false
            case "create_recipe": output = try await createRecipe(arguments)
            case "update_recipe": output = try await updateRecipe(arguments)
            case "delete_recipe": output = try deleteRecipe(arguments)
            case "set_recipe_image": output = try await setRecipeImage(arguments)
            default: throw ToolError("У сервера нет инструмента «\(name)».")
            }
            if changed {
                ExternalChanges.post()
            }
            return CallTool.Result(content: [.text(text: ToolOutput.json(output), annotations: nil, _meta: nil)])
        } catch let error as ToolError {
            return failure(error.message)
        } catch let error as StoreError {
            return failure(error.message)
        } catch {
            return failure("Не получилось: \(error)")
        }
    }

    private func failure(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }

    /// Reports the database without creating it: before the app's first launch there is none.
    private func status() throws -> Value {
        var database: [String: Value] = ["file": .string(location.databaseFile.path(percentEncoded: false))]
        if FileManager.default.fileExists(atPath: location.databaseFile.path(percentEncoded: false)) {
            let opened = try self.database()
            database["exists"] = true
            database["migrations"] = .array(try opened.appliedMigrations().map { .string($0) })
            database["products"] = .int(try opened.products(ProductQuery(), limit: 1).total)
            database["recipes"] = .int(try opened.recipeCards(RecipeQuery(), limit: 1).total)
            database["categories"] = .int(try opened.categories().count)
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

    private func listAisles() throws -> Value {
        .object(["aisles": .array(try database().aisles().map { .string($0.name) })])
    }
}
