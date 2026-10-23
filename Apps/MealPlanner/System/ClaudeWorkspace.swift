import CryptoKit
import Foundation
import MealCore

/// The folder the «… с Claude» buttons open Claude Code sessions in, with instructions on Meal Planner's data
/// and tools. It holds only CLAUDE.md: Claude Desktop treats a folder with `.claude/settings.json` as having
/// dangerous features and asks to trust it again on every link. A file the user changed stays as it is; one
/// still holding the default of an earlier version is updated.
struct ClaudeWorkspace {
    let folder: URL

    /// «Meal Planner» in the app's data folder; Claude Desktop names the sessions' project after it.
    init(dataDirectory: URL) {
        folder = dataDirectory.appending(path: "Meal Planner", directoryHint: .isDirectory)
    }

    var instructionsFile: URL {
        folder.appending(path: "CLAUDE.md")
    }

    func prepare(replacing earlier: Set<String> = Self.earlierDefaults) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let current = (try? Data(contentsOf: instructionsFile)).map(Self.digest)
        if current == nil || earlier.contains(current ?? "") {
            try Data(Self.instructions.utf8).write(to: instructionsFile, options: .atomic)
        }
    }

    /// SHA-256 of the CLAUDE.md earlier versions wrote: a file that still matches one was never edited. Before
    /// changing `instructions`, add the digest of the text it replaces.
    static let earlierDefaults: Set<String> = []

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static let instructions = """
        # Meal Planner & Recipes: рецепты, продукты и КБЖУ

        Meal Planner & Recipes — личное приложение для Mac: рецепты с КБЖУ, база продуктов, запасы дома, список \
        покупок и меню на неделю. Едят двое. Данные — только через инструменты MCP-сервера Meal Planner; базу и \
        файлы приложения напрямую не трогай.

        Инструменты:
        - продукты: `search_products`, `get_product`, `upsert_product`, `merge_products`, `list_aisles`;
        - категории рецептов: `list_categories`, `create_category`, `update_category`, `delete_category`;
        - рецепты: `search_recipes`, `get_recipe`, `create_recipe`, `update_recipe`, `delete_recipe` (в корзину), \
        `set_recipe_image`;
        - `get_status` — версия сервера и состояние базы.

        ## Правила

        \(ClaudeRequest.rules)
        - Ингредиенты в `create_recipe` и `update_recipe` — строкой («40 г феты»), если продукт уже есть в базе, \
        или объектом `{name, amount, unit, note, optional, group}`, если его может не быть: из `name` создаётся \
        продукт. После сохранения проверь `created_products` — заполни их КБЖУ — и `matched_by_search` — верно \
        ли подобраны продукты.
        - \(ClaudeRequest.nutritionRules)

        ## Рецепт по ссылке

        Прочитай страницу (разметка schema.org/Recipe, если есть), проверь через `search_recipes`, нет ли рецепта \
        уже, создай его через `create_recipe` с фото (`image_url`), источником и видео, заполни новые продукты. В \
        конце — что добавлено и КБЖУ на порцию.

        Отвечай по-русски, коротко и с цифрами. Файлы в этой папке менять не нужно.

        """
}
