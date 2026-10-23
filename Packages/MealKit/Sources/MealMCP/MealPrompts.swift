import Foundation
import MCP
import MealCore

/// Ready requests for Claude Desktop's «+» menu and the app's «Открыть в Claude» buttons: each one walks Claude
/// through a whole task with the server's tools.
public enum MealPrompts {
    public static let all: [Prompt] = [
        Prompt(
            name: "import_recipe", title: "Импорт рецепта по ссылке",
            description:
                "Прочитать рецепт на сайте или в видео и завести его в приложение: фото, ингредиенты, шаги и КБЖУ.",
            arguments: [
                Prompt.Argument(
                    name: "url", title: "Ссылка", description: "Страница рецепта или видео.", required: true),
                Prompt.Argument(
                    name: "category", title: "Категория", description: "Куда положить рецепт: «Завтраки».",
                    required: false),
            ]),
        Prompt(
            name: "fill_recipe", title: "Дозаполнить рецепт",
            description: "Найти, чего не хватает рецепту — КБЖУ продуктов, пересчётов, времени, шагов, — и заполнить.",
            arguments: [
                Prompt.Argument(
                    name: "recipe", title: "Рецепт", description: "Id или название рецепта.", required: true)
            ]),
        Prompt(
            name: "fill_nutrition", title: "Заполнить КБЖУ продуктов",
            description: "Заполнить КБЖУ и пересчёты у продуктов, где их нет или они помечены «проверить».",
            arguments: [
                Prompt.Argument(
                    name: "products", title: "Продукты",
                    description: "Названия через запятую; пусто — все продукты без КБЖУ.", required: false)
            ]),
        Prompt(
            name: "migrate_from_notion", title: "Перенести рецепты из Notion",
            description: "Перенести рецепты из базы Notion: фото, ингредиенты с количеством, шаги, категории и ссылки.",
            arguments: [
                Prompt.Argument(
                    name: "database", title: "База в Notion",
                    description: "Название или ссылка базы рецептов; по умолчанию Recipes.", required: false)
            ]),
    ]

    /// The prompt's message with its arguments filled in.
    public static func get(_ name: String, arguments: [String: String] = [:]) throws -> GetPrompt.Result {
        let value = { (key: String) -> String? in
            arguments[key].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let prompt = all.first(where: { $0.name == name }) else {
            throw MCPError.invalidParams("Нет промпта «\(name)».")
        }
        let text: String
        switch name {
        case "import_recipe":
            guard let url = value("url") else { throw MCPError.invalidParams("Нужна ссылка: «url».") }
            text = ClaudeRequest.importRecipe(url: url, category: value("category"))
        case "fill_recipe":
            guard let recipe = value("recipe") else { throw MCPError.invalidParams("Нужен рецепт: «recipe».") }
            text = ClaudeRequest.fillRecipe(Int(recipe) == nil ? "«\(recipe)»" : "с id \(recipe)")
        case "fill_nutrition":
            text = ClaudeRequest.fillNutrition(value("products"))
        default:
            text = ClaudeRequest.migrateFromNotion(value("database") ?? "Recipes")
        }
        return GetPrompt.Result(description: prompt.description, messages: [.user(.text(text: text))])
    }
}
