import Foundation
import MCP
import MealCore
import MealStore

extension MealTools {
    static let categoryTools: [Tool] = [
        Tool(
            name: "list_categories", title: "Категории и приёмы пищи",
            description:
                "Категории рецептов по порядку, с цветом и числом рецептов, и приёмы пищи (завтрак, обед, ужин, перекус), на которые рецепт может подходить.",
            inputSchema: schema([:]), annotations: readOnly),
        Tool(
            name: "create_category", title: "Новая категория",
            description: "Создаёт категорию рецептов в конце списка.",
            inputSchema: schema(
                [
                    "name": string("Название: «Завтраки», «Супы»."),
                    "color": choice(
                        TagColor.allCases.map(\.rawValue), "Цвет метки; по умолчанию следующий по палитре."),
                ], required: ["name"]),
            annotations: changes),
        Tool(
            name: "update_category", title: "Изменить категорию",
            description: "Переименовывает категорию, меняет её цвет или место в списке.",
            inputSchema: schema(
                [
                    "category": string("Категория: id или название."),
                    "name": string("Новое название."),
                    "color": choice(TagColor.allCases.map(\.rawValue), "Новый цвет."),
                    "position": integer("Новое место в списке, с 1."),
                ], required: ["category"]),
            annotations: idempotent),
        Tool(
            name: "delete_category", title: "Удалить категорию",
            description: "Удаляет категорию; рецепты остаются — в других категориях или без категории.",
            inputSchema: schema(["category": string("Категория: id или название.")], required: ["category"]),
            annotations: destructive),
    ]

    func listCategories() throws -> Value {
        let database = try database()
        return .object([
            "categories": .array(
                try database.categorySummaries().map { summary in
                    .object([
                        "id": ToolOutput.id(summary.id), "name": .string(summary.category.name),
                        "color": .string(summary.category.color.rawValue), "recipes": .int(summary.count),
                    ])
                }),
            "meal_types": .array(try database.mealTypes().map { .string($0.name) }),
        ])
    }

    func createCategory(_ arguments: Arguments) throws -> Value {
        let database = try database()
        var category = try database.newCategory(named: try arguments.required("name"))
        if let color = try arguments.string("color") {
            category.color = try tagColor(color)
            category = try database.save(category)
        }
        return category.json
    }

    func updateCategory(_ arguments: Arguments) throws -> Value {
        let database = try database()
        var category = try category(reference: try arguments.required("category"), database)
        if let name = try arguments.string("name"), !name.isEmpty {
            category.name = name
        }
        if let color = try arguments.string("color") {
            category.color = try tagColor(color)
        }
        category = try database.save(category)
        if let position = try arguments.int("position") {
            var ids = try database.categories().map(\.id).filter { $0 != category.id }
            ids.insert(category.id, at: min(max(position - 1, 0), ids.count))
            try database.reorderCategories(ids)
            category = try database.categories().first { $0.id == category.id } ?? category
        }
        return category.json
    }

    func deleteCategory(_ arguments: Arguments) throws -> Value {
        let database = try database()
        let category = try category(reference: try arguments.required("category"), database)
        try database.deleteCategory(id: category.id)
        return .object(["deleted": .string(category.name)])
    }

    // MARK: - Lookups

    func categoryNames(_ database: AppDatabase) throws -> [Int64: String] {
        Dictionary(uniqueKeysWithValues: try database.categories().map { ($0.id, $0.name) })
    }

    func mealTypeNames(_ database: AppDatabase) throws -> [Int64: String] {
        Dictionary(uniqueKeysWithValues: try database.mealTypes().map { ($0.id, $0.name) })
    }

    func category(reference: String, _ database: AppDatabase) throws -> RecipeCategory {
        let categories = try database.categories()
        let key = SearchText.normalized(reference)
        guard
            let category = categories.first(where: { String($0.id) == reference })
                ?? categories.first(where: { SearchText.normalized($0.name) == key })
        else {
            throw ToolError(
                "Нет категории «\(reference)». Категории: \(categories.map(\.name).joined(separator: ", ")).")
        }
        return category
    }

    func mealType(_ name: String, _ database: AppDatabase) throws -> MealType {
        let meals = try database.mealTypes()
        let key = SearchText.normalized(name)
        // «завтрак», «Завтраки», «на завтрак»: the stem decides.
        guard
            let meal = meals.first(where: {
                SearchText.terms($0.name) == SearchText.terms(key)
                    || SearchText.terms(key).contains(SearchText.terms($0.name).first ?? "")
            })
        else {
            throw ToolError("Нет приёма пищи «\(name)». Есть: \(meals.map(\.name).joined(separator: ", ")).")
        }
        return meal
    }

    private func tagColor(_ text: String) throws -> TagColor {
        guard
            let color = TagColor(rawValue: text.lowercased())
                ?? TagColor.allCases.first(where: { $0.title.lowercased() == text.lowercased() })
        else {
            throw ToolError("Нет цвета «\(text)». Цвета: \(TagColor.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        return color
    }
}

extension RecipeCategory {
    fileprivate var json: Value {
        .object([
            "id": ToolOutput.id(id), "name": .string(name), "color": .string(color.rawValue),
            "position": .int(position + 1),
        ])
    }
}
