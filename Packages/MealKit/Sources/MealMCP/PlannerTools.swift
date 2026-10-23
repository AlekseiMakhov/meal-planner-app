import Foundation
import MCP
import MealCore
import MealStore

extension MealTools {
    static let plannerTools: [Tool] = [
        Tool(
            name: "get_week_plan", title: "Меню на неделю",
            description: """
                Меню недели: по дням и приёмам пищи — блюда (id, рецепт или текст, порции, приготовлено ли, short — дома \
                не хватит на него продуктов с учётом блюд до него), КБЖУ за день на человека и всего и в среднем за день.
                """,
            inputSchema: schema([
                "week": string("Любой день недели, «2026-10-23»; по умолчанию — текущая неделя.")
            ]),
            annotations: readOnly),
        Tool(
            name: "plan_meal", title: "Добавить в меню",
            description:
                "Ставит блюдо в меню: рецепт (на его порции, если не сказано иначе) или текст — «ужин в гостях».",
            inputSchema: schema(
                [
                    "date": string("День, «2026-10-23», «сегодня» или «завтра»."),
                    "meal": string("Приём пищи: завтрак, обед, ужин, перекус или свой."),
                    "recipe": string("Рецепт: id или название."),
                    "text": string("Вместо рецепта — текст."),
                    "servings": integer("Порций."),
                ], required: ["date", "meal"]),
            annotations: changes),
        Tool(
            name: "move_meal", title: "Перенести блюдо",
            description: "Переносит блюдо меню на другой день или приём пищи, меняет порции; copy: true — копия.",
            inputSchema: schema(
                [
                    "id": integer("Id блюда из get_week_plan."),
                    "date": string("Новый день."),
                    "meal": string("Новый приём пищи."),
                    "servings": integer("Новое число порций."),
                    "copy": boolean("Оставить блюдо и поставить копию."),
                ], required: ["id"]),
            annotations: changes),
        Tool(
            name: "remove_meal", title: "Убрать из меню",
            description: "Убирает блюда из меню; то, что приготовленное блюдо списало из запасов, остаётся списанным.",
            inputSchema: schema(
                ["ids": .object(["type": "array", "items": ["type": "integer"], "description": "Id блюд."])],
                required: ["ids"]),
            annotations: destructive),
        Tool(
            name: "mark_cooked", title: "Приготовлено",
            description: """
                Отмечает блюдо приготовленным и списывает продукты из запасов. Без confirm только показывает, что \
                спишется (would_take) — покажи это и спроси, прежде чем вызывать с confirm: true. amounts поправляют \
                количества: {"Яйцо куриное": 2}. undo: true — отменить «Приготовлено» и вернуть списанное.
                """,
            inputSchema: schema(
                [
                    "id": integer("Id блюда из get_week_plan."),
                    "confirm": boolean("Списать и отметить."),
                    "amounts": .object([
                        "type": "object", "additionalProperties": ["type": "number"],
                        "description": "Продукт → сколько списать в основной единице; 0 — не списывать.",
                    ]),
                    "undo": boolean("Отменить «Приготовлено»."),
                ], required: ["id"]),
            annotations: changes),
        Tool(
            name: "week_nutrition", title: "КБЖУ недели",
            description: "КБЖУ меню по дням — на человека (порция каждого блюда) и всего — и в среднем за день.",
            inputSchema: schema(["week": string("Любой день недели; по умолчанию — текущая.")]),
            annotations: readOnly),
    ]

    // MARK: - Reading

    func getWeekPlan(_ arguments: Arguments) throws -> Value {
        let database = try database()
        let plan = try database.weekPlan(starting: try week(arguments))
        let today = Day.today()
        let supply = plan.supply(from: max(today, plan.start))
        let meals = Dictionary(uniqueKeysWithValues: plan.mealTypes.map { ($0.id, $0.name) })
        let days: [Value] = plan.days.map { day in
            let dishes: [Value] = plan.entries.filter { $0.day == day }.map { entry in
                let recipe = entry.recipeID.flatMap { plan.recipes[$0] }
                return .object([
                    "id": ToolOutput.id(entry.id),
                    "meal": ToolOutput.text(meals[entry.mealTypeID]),
                    "recipe_id": entry.recipeID.map(ToolOutput.id) ?? .null,
                    "title": .string(recipe?.recipe.title ?? entry.text ?? ""),
                    "servings": entry.recipeID == nil ? .null : .int(entry.servings),
                    "cooked": .bool(entry.isCooked),
                    "short": .bool(supply.shortEntries.contains(entry.id)),
                ])
            }
            return .object([
                "date": .string(day.description),
                "weekday": .string(["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"][day.weekday - 1]),
                "dishes": .array(dishes),
                "nutrition": dayNutrition(plan.nutrition(on: day)),
            ])
        }
        return .object([
            "week": .string("\(plan.start)…\(plan.start.adding(days: 6))"),
            "meals": .array(plan.mealTypes.map { .string($0.name) }),
            "days": .array(days),
            "average_day": plan.averageDay.map(dayNutrition) ?? .null,
        ])
    }

    func weekNutrition(_ arguments: Arguments) throws -> Value {
        let plan = try database().weekPlan(starting: try week(arguments))
        return .object([
            "days": .array(
                plan.days.map { day in
                    .object(["date": .string(day.description), "nutrition": dayNutrition(plan.nutrition(on: day))])
                }),
            "average_day": plan.averageDay.map(dayNutrition) ?? .null,
        ])
    }

    private func dayNutrition(_ nutrition: DayNutrition) -> Value {
        guard !nutrition.isEmpty else { return .null }
        return .object([
            "per_person": ToolOutput.nutrition(nutrition.perPerson),
            "total": ToolOutput.nutrition(nutrition.total),
            "dishes_counted": .int(nutrition.counted),
            "dishes_without_nutrition": .int(nutrition.uncounted),
        ])
    }

    // MARK: - Changing

    func planMeal(_ arguments: Arguments) throws -> Value {
        let database = try database()
        let day = try date(try arguments.required("date"))
        let meal = try mealType(try arguments.required("meal"), database)
        var recipe: Recipe.ID?
        if let reference = try arguments.nonEmpty("recipe") {
            recipe = try recipeID(reference, database)
        }
        let text = try arguments.nonEmpty("text")
        guard recipe != nil || text != nil else { throw ToolError("Нужно recipe или text.") }
        let entry = try database.planMeal(
            on: day, meal: meal.id, recipe: recipe, text: text, servings: try arguments.int("servings"))
        return try entryResult(entry, database)
    }

    func moveMeal(_ arguments: Arguments) throws -> Value {
        let database = try database()
        guard let id = try arguments.int("id").map(Int64.init), var entry = try database.planEntry(id: id) else {
            throw ToolError("Нет блюда с таким id: возьми его из get_week_plan.")
        }
        let day = try arguments.nonEmpty("date").map(date) ?? entry.day
        let meal = try arguments.nonEmpty("meal").map { try mealType($0, database).id } ?? entry.mealTypeID
        if try arguments.bool("copy") == true {
            entry = try database.copyPlanEntry(id, to: day, meal: meal)
        } else if day != entry.day || meal != entry.mealTypeID {
            try database.movePlanEntry(id, to: day, meal: meal)
        }
        if let servings = try arguments.int("servings") {
            try database.setPlanServings(servings, entry: entry.id)
        }
        guard let moved = try database.planEntry(id: entry.id) else { throw ToolError("Блюда больше нет.") }
        return try entryResult(moved, database)
    }

    func removeMeal(_ arguments: Arguments) throws -> Value {
        let database = try database()
        guard let values = try arguments.array("ids"), !values.isEmpty else { throw ToolError("Нужно «ids».") }
        let ids = Set(
            try values.map { value in
                guard let id = try Arguments(["id": value]).int("id") else { throw ToolError("«ids» — числа.") }
                return Int64(id)
            })
        try database.removePlanEntries(ids)
        return .object(["removed": .int(ids.count)])
    }

    func markCooked(_ arguments: Arguments) throws -> Value {
        let database = try database()
        guard let id = try arguments.int("id").map(Int64.init), let entry = try database.planEntry(id: id) else {
            throw ToolError("Нет блюда с таким id: возьми его из get_week_plan.")
        }
        if try arguments.bool("undo") == true {
            try database.undoCooked(id)
            return .object(["id": ToolOutput.id(id), "cooked": false, "returned_to_pantry": true])
        }
        guard entry.recipeID != nil else { throw ToolError("Это блюдо — текст, отмечать нечего.") }
        guard !entry.isCooked else { throw ToolError("Блюдо уже отмечено приготовленным; undo: true — отменить.") }
        var use = try database.cookingUse(of: id)
        if let overrides = try arguments.object("amounts") {
            for (name, value) in overrides {
                guard let amount = try Arguments(["value": value]).double("value"), amount >= 0 else {
                    throw ToolError("amounts: «\(name)» — число не меньше нуля.")
                }
                let key = SearchText.normalized(name)
                guard
                    let index = use.firstIndex(where: {
                        SearchText.normalized($0.product.name) == key || String($0.id) == name
                    })
                else {
                    throw ToolError(
                        "amounts: «\(name)» нет среди того, что спишется: \(use.map(\.product.name).joined(separator: ", "))."
                    )
                }
                use[index].amount = amount
            }
        }
        let wouldTake: [Value] = use.map { item in
            .object([
                "product": .string(item.product.name), "amount": ToolOutput.number(item.amount, places: 2),
                "unit": .string(item.product.baseUnit.rawValue), "at_home": ToolOutput.number(item.atHome, places: 2),
            ])
        }
        guard try arguments.bool("confirm") == true else {
            return .object([
                "id": ToolOutput.id(id), "would_take": .array(wouldTake),
                "next": "Покажи, что спишется, и после согласия вызови mark_cooked с confirm: true.",
            ])
        }
        try database.markCooked(id, using: Dictionary(uniqueKeysWithValues: use.map { ($0.id, $0.amount) }))
        return .object(["id": ToolOutput.id(id), "cooked": true, "taken": .array(wouldTake)])
    }

    // MARK: - Helpers

    private func entryResult(_ entry: PlanEntry, _ database: AppDatabase) throws -> Value {
        let meals = Dictionary(uniqueKeysWithValues: try database.mealTypes().map { ($0.id, $0.name) })
        let title = try entry.recipeID.flatMap { try database.recipe(id: $0)?.recipe.title } ?? entry.text ?? ""
        return .object([
            "id": ToolOutput.id(entry.id),
            "date": .string(entry.day.description),
            "meal": ToolOutput.text(meals[entry.mealTypeID]),
            "title": .string(title),
            "servings": entry.recipeID == nil ? .null : .int(entry.servings),
            "cooked": .bool(entry.isCooked),
        ])
    }

    /// The Monday of the week a call names, this week by default.
    func week(_ arguments: Arguments) throws -> Day {
        try (arguments.nonEmpty("week").map(date) ?? Day.today()).weekStart
    }

    /// «2026-10-23», «сегодня», «завтра», «today», «tomorrow».
    func date(_ text: String) throws -> Day {
        switch SearchText.normalized(text) {
        case "сегодня", "today": return Day.today()
        case "завтра", "tomorrow": return Day.today().adding(days: 1)
        case "вчера", "yesterday": return Day.today().adding(days: -1)
        default:
            guard let day = Day(text.trimmingCharacters(in: .whitespaces)) else {
                throw ToolError("«\(text)» — не день: нужно «2026-10-23», «сегодня» или «завтра».")
            }
            return day
        }
    }
}
