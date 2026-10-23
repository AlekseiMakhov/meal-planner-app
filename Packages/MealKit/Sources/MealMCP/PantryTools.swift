import Foundation
import MCP
import MealCore
import MealStore

extension MealTools {
    private static let unitDescription =
        "Единица количества: g, kg, ml, l, tsp, tbsp, cup, pcs, clove, bunch… или по-русски («г», «л», «шт.»); без неё — основная единица продукта."

    static let pantryTools: [Tool] = [
        Tool(
            name: "get_pantry", title: "Запасы",
            description:
                "Что есть дома: количество в основной единице продукта (g, ml или pcs), статус in_stock / low / out. quantity null — есть, без счёта (соль, специи).",
            inputSchema: schema(
                [
                    "query": string("Слова из названия продукта."),
                    "aisles": strings("Только эти отделы."),
                    "status": .object([
                        "type": "array", "items": ["type": "string", "enum": ["in_stock", "low", "out"]],
                        "description":
                            "Только с этими статусами: in_stock — есть, low — заканчивается, out — закончилось.",
                    ]),
                    "sort": choice(["aisle", "name", "quantity", "updated"], "Порядок; по умолчанию aisle."),
                ].merging(page) { first, _ in first }),
            annotations: readOnly),
        Tool(
            name: "set_pantry", title: "Задать запасы",
            description: """
                Задаёт, сколько чего дома, сразу для нескольких продуктов. quantity — сколько есть сейчас (с unit пересчитается \
                в основную единицу продукта); без quantity — «есть, без счёта»; 0 — закончилось. remove — перестать вести \
                продукт в запасах.
                """,
            inputSchema: schema([
                "items": .object([
                    "type": "array",
                    "items": [
                        "type": "object", "additionalProperties": false, "required": ["product"],
                        "properties": [
                            "product": ["type": "string", "description": "Продукт: название, синоним или id."],
                            "quantity": ["type": "number", "description": "Сколько есть."],
                            "unit": .object(["type": "string", "description": .string(unitDescription)]),
                            "low": ["type": "boolean", "description": "Заканчивается."],
                        ],
                    ],
                    "description": "Продукты и их количество.",
                ]),
                "remove": strings("Продукты, которые убрать из запасов."),
            ]),
            annotations: idempotent),
        Tool(
            name: "adjust_pantry", title: "Пополнить или списать",
            description: """
                Меняет запасы на разницу: «купил 10 яиц» — add, «ушло 200 г муки» — take, «закончилась соль» — out. \
                Строка «10 яиц» значит add.
                """,
            inputSchema: schema([
                "items": .object([
                    "type": "array",
                    "items": [
                        "anyOf": [
                            ["type": "string"],
                            [
                                "type": "object", "additionalProperties": false, "required": ["product"],
                                "properties": [
                                    "product": ["type": "string", "description": "Продукт: название, синоним или id."],
                                    "add": ["type": "number", "description": "Сколько прибавить."],
                                    "take": ["type": "number", "description": "Сколько убавить."],
                                    "unit": .object(["type": "string", "description": .string(unitDescription)]),
                                ],
                            ],
                        ]
                    ],
                    "description": "Что прибавить или убавить.",
                ]),
                "out": strings("Что закончилось."),
            ]),
            annotations: changes),
        Tool(
            name: "get_shopping_list", title: "Список покупок",
            description:
                "Список покупок по отделам магазина: что купить, сколько, для каких блюд; купленное — в конце.",
            inputSchema: schema(
                [
                    "query": string("Слова из названия."),
                    "aisles": strings("Только эти отделы."),
                    "checked": boolean("true — только купленное, false — только то, что ещё купить."),
                    "recipe": string("Только то, что нужно для этого рецепта: id или название."),
                    "sort": choice(["aisle", "name", "created", "manual"], "Порядок; по умолчанию aisle."),
                ].merging(page) { first, _ in first }),
            annotations: readOnly),
        Tool(
            name: "add_to_shopping_list", title: "В покупки",
            description: """
                Добавляет в список покупок. items — строки («молоко 1 л», «хлеб») или объекты; продукт ищется в базе, а то, \
                чего в ней нет, записывается текстом («Батарейки»). recipe — недостающее для рецепта с учётом запасов: \
                нехватка в основной единице продукта, с рецептом в «для». То, что уже в списке, прибавляется к нему; тот же \
                рецепт второй раз ничего не добавляет.
                """,
            inputSchema: schema([
                "items": .object([
                    "type": "array",
                    "items": [
                        "anyOf": [
                            ["type": "string"],
                            [
                                "type": "object", "additionalProperties": false,
                                "properties": [
                                    "product": [
                                        "type": "string", "description": "Продукт базы: название, синоним или id.",
                                    ],
                                    "text": ["type": "string", "description": "То, чего нет в базе: «Батарейки»."],
                                    "amount": ["type": "number"],
                                    "unit": .object(["type": "string", "description": .string(unitDescription)]),
                                    "for": ["type": "string", "description": "Для чего: название блюда."],
                                ],
                            ],
                        ]
                    ],
                    "description": "Что купить.",
                ]),
                "recipe": string("Рецепт, для которого купить недостающее: id или название."),
                "servings": integer("Порций рецепта; по умолчанию — как в рецепте."),
                "week": string(
                    "Любой день недели: недостающее на блюда меню этой недели, с сегодняшнего дня, с днём в «для»."),
            ]),
            annotations: changes),
        Tool(
            name: "check_shopping_items", title: "Отметить купленное",
            description: """
                Отмечает позиции купленными (или снимает отметку). stock: true — сразу положить купленное в запасы в том \
                количестве, что было в списке, и убрать из списка.
                """,
            inputSchema: schema(
                [
                    "ids": .object(["type": "array", "items": ["type": "integer"], "description": "Id позиций."]),
                    "checked": boolean("true — куплено (по умолчанию), false — снять отметку."),
                    "stock": boolean("Положить купленное в запасы."),
                ], required: ["ids"]),
            annotations: idempotent),
        Tool(
            name: "remove_shopping_items", title: "Убрать из покупок",
            description: "Убирает позиции из списка покупок, запасы не меняются.",
            inputSchema: schema(
                ["ids": .object(["type": "array", "items": ["type": "integer"], "description": "Id позиций."])],
                required: ["ids"]),
            annotations: destructive),
        Tool(
            name: "clear_checked", title: "Очистить купленное",
            description:
                "Убирает купленное из списка. stock: true — то, что ещё не в запасах, сначала положить в запасы.",
            inputSchema: schema(["stock": boolean("Сначала положить купленное в запасы.")]),
            annotations: destructive),
    ]

    // MARK: - Pantry

    func getPantry(_ arguments: Arguments) throws -> Value {
        let database = try database()
        var query = PantryQuery(text: try arguments.string("query") ?? "")
        if let names = try arguments.strings("aisles") {
            query.aisleIDs = Set(try names.map { try aisle($0, database).id })
        }
        let statuses: [String: PantryStatus] = ["in_stock": .inStock, "low": .low, "out": .out]
        if let names = try arguments.strings("status") {
            query.statuses = Set(
                try names.map { name in
                    guard let status = statuses[name] else {
                        throw ToolError("Нет статуса «\(name)»: in_stock, low, out.")
                    }
                    return status
                })
        }
        let keys: [String: PantryQuery.SortKey] = [
            "aisle": .aisle, "name": .name, "quantity": .quantity, "updated": .updatedAt,
        ]
        let sort = try arguments.string("sort") ?? "aisle"
        guard let key = keys[sort] else { throw ToolError("Нет сортировки «\(sort)».") }
        query.sort = [SortTerm(key, try arguments.bool("descending") == true ? .descending : .ascending)]

        let offset = try arguments.offset()
        let page = try database.pantry(query, limit: try arguments.limit(), offset: offset)
        let aisles = try aisleNames(database)
        return .object([
            "total": .int(page.total),
            "items": .array(page.rows.map { ToolOutput.pantry($0, aisles: aisles) }),
            "next_cursor": offset + page.rows.count < page.total ? .string(String(offset + page.rows.count)) : .null,
        ])
    }

    func setPantry(_ arguments: Arguments) throws -> Value {
        let database = try database()
        var changed: [Product.ID] = []
        var notes: [String] = []
        for (index, value) in (try arguments.array("items") ?? []).enumerated() {
            guard let object = value.objectValue else { throw ToolError("items[\(index + 1)] — объект.") }
            let item = Arguments(object)
            let product = try pantryProduct(try item.required("product"), database)
            var quantity: Double?
            if let amount = try item.double("quantity") {
                quantity = try baseAmount(amount, try item.nonEmpty("unit"), of: product, notes: &notes)
            }
            try database.setPantry(product.id, quantity: quantity, isLow: try item.bool("low"))
            changed.append(product.id)
        }
        var removed: [String] = []
        if let names = try arguments.strings("remove"), !names.isEmpty {
            let products = try names.map { try pantryProduct($0, database) }
            try database.removeFromPantry(Set(products.map(\.id)))
            removed = products.map(\.name)
        }
        guard !changed.isEmpty || !removed.isEmpty else { throw ToolError("Нужно items или remove.") }
        return try pantryResult(changed, removed: removed, notes: notes, database)
    }

    func adjustPantry(_ arguments: Arguments) throws -> Value {
        let database = try database()
        var added: [Product.ID: Double?] = [:]
        var taken: [Product.ID: Double] = [:]
        var notes: [String] = []
        for (index, value) in (try arguments.array("items") ?? []).enumerated() {
            if let text = value.stringValue {
                for typed in try database.readLines(text) {
                    let product = try matched(typed.match, name: typed.name)
                    let amount = try typed.amount.map {
                        try baseAmount($0, typed.unit?.rawValue, of: product, notes: &notes)
                    }
                    added[product.id] = sum(added[product.id] ?? nil, amount ?? nil)
                }
            } else if let object = value.objectValue {
                let item = Arguments(object)
                let product = try pantryProduct(try item.required("product"), database)
                let unit = try item.nonEmpty("unit")
                if let amount = try item.double("add") {
                    let base = try baseAmount(amount, unit, of: product, notes: &notes)
                    added[product.id] = sum(added[product.id] ?? nil, base)
                } else if let amount = try item.double("take") {
                    guard let base = try baseAmount(amount, unit, of: product, notes: &notes) else { continue }
                    taken[product.id, default: 0] += base
                } else {
                    added[product.id] = added[product.id] ?? nil
                }
            } else {
                throw ToolError("items[\(index + 1)] — строка или объект.")
            }
        }
        var ranOut: [Product.ID] = []
        for name in try arguments.strings("out") ?? [] {
            let product = try pantryProduct(name, database)
            try database.setPantry(product.id, quantity: 0)
            ranOut.append(product.id)
        }
        if !added.isEmpty { try database.addToPantry(added) }
        if !taken.isEmpty { try database.takeFromPantry(taken) }
        let changed = Array(added.keys) + Array(taken.keys) + ranOut
        guard !changed.isEmpty else { throw ToolError("Нужно items или out.") }
        return try pantryResult(changed, removed: [], notes: notes, database)
    }

    private func sum(_ first: Double?, _ second: Double?) -> Double? {
        switch (first, second) {
        case (let first?, let second?): first + second
        case (let first?, nil): first
        case (nil, let second?): second
        case (nil, nil): nil
        }
    }

    /// The amount in the product's base unit; one that does not convert is noted and counts as «some».
    private func baseAmount(_ amount: Double, _ unitText: String?, of product: Product, notes: inout [String]) throws
        -> Double?
    {
        guard amount >= 0 else { throw ToolError("Количество не бывает отрицательным.") }
        var unit = product.baseUnit.unit
        if let unitText {
            guard let parsed = MeasureUnit(parsing: unitText) else { throw ToolError("Нет единицы «\(unitText)».") }
            unit = parsed
        }
        guard let converted = product.units.inBaseUnit(amount, unit) else {
            notes.append(
                "«\(product.name)»: \(ToolOutput.number(amount, places: 2)) \(unit.rawValue) не пересчитать в \(product.baseUnit.rawValue) — задай пересчёт через upsert_product; отмечено, что есть."
            )
            return nil
        }
        return converted
    }

    private func pantryResult(_ ids: [Product.ID], removed: [String], notes: [String], _ database: AppDatabase) throws
        -> Value
    {
        let items = try database.pantryItems(for: ids)
        let aisles = try aisleNames(database)
        var entries: [Value] = []
        for id in Set(ids).sorted() {
            guard let product = try database.product(id: id), let item = items[id] else { continue }
            entries.append(ToolOutput.pantry(PantryEntry(product: product, item: item), aisles: aisles))
        }
        var result: [String: Value] = ["items": .array(entries)]
        if !removed.isEmpty { result["removed"] = .array(removed.map(Value.string)) }
        if !notes.isEmpty { result["notes"] = .array(notes.map(Value.string)) }
        return .object(result)
    }

    /// The product a pantry or shopping call names: by id, or by name — one product, or a mistake to fix.
    private func pantryProduct(_ reference: String, _ database: AppDatabase) throws -> Product {
        if let id = Int64(reference), let product = try database.product(id: id) {
            return product
        }
        return try matched(try database.matchProduct(named: reference), name: reference)
    }

    private func matched(_ match: ProductMatch, name: String) throws -> Product {
        switch match {
        case .found(let product): return product
        case .ambiguous(let candidates):
            let names = candidates.map { "«\($0.name)» (id \($0.id))" }.joined(separator: ", ")
            throw ToolError("«\(name)»: подходят \(names). Укажи продукт точнее или его id.")
        case .none:
            throw ToolError("Продукта «\(name)» нет в базе. Создай его через upsert_product.")
        }
    }

    // MARK: - Shopping list

    func getShoppingList(_ arguments: Arguments) throws -> Value {
        let database = try database()
        var query = ShoppingQuery(text: try arguments.string("query") ?? "")
        if let names = try arguments.strings("aisles") {
            query.aisleIDs = Set(try names.map { try aisle($0, database).id })
        }
        query.isChecked = try arguments.bool("checked")
        if let reference = try arguments.nonEmpty("recipe") {
            query.recipeID = try recipeID(reference, database)
        }
        let keys: [String: ShoppingQuery.SortKey] = [
            "aisle": .aisle, "name": .name, "created": .createdAt, "manual": .manual,
        ]
        let sort = try arguments.string("sort") ?? "aisle"
        guard let key = keys[sort] else { throw ToolError("Нет сортировки «\(sort)».") }
        query.sort = [SortTerm(key, try arguments.bool("descending") == true ? .descending : .ascending)]

        let offset = try arguments.offset()
        let page = try database.shopping(query, limit: try arguments.limit(), offset: offset)
        let aisles = try aisleNames(database)
        return .object([
            "total": .int(page.total),
            "items": .array(page.rows.map { ToolOutput.shopping($0, aisles: aisles) }),
            "next_cursor": offset + page.rows.count < page.total ? .string(String(offset + page.rows.count)) : .null,
        ])
    }

    func addToShoppingList(_ arguments: Arguments) throws -> Value {
        let database = try database()
        var additions: [ShoppingAddition] = []
        for (index, value) in (try arguments.array("items") ?? []).enumerated() {
            if let text = value.stringValue {
                let lines = try database.readLines(text)
                if lines.isEmpty { throw ToolError("items[\(index + 1)] «\(text)»: не понятно, что купить.") }
                for typed in lines {
                    if case .found(let product) = typed.match {
                        additions.append(ShoppingAddition(product: product.id, amount: typed.amount, unit: typed.unit))
                    } else {
                        additions.append(
                            ShoppingAddition(
                                text: typed.name.prefix(1).uppercased() + typed.name.dropFirst(), amount: typed.amount,
                                unit: typed.unit))
                    }
                }
            } else if let object = value.objectValue {
                let item = Arguments(object)
                var unit: MeasureUnit?
                if let text = try item.nonEmpty("unit") {
                    guard let parsed = MeasureUnit(parsing: text) else { throw ToolError("Нет единицы «\(text)».") }
                    unit = parsed
                }
                let reason = try item.nonEmpty("for").map { ShoppingReason(title: $0) }
                if let reference = try item.nonEmpty("product") {
                    let product = try pantryProduct(reference, database)
                    additions.append(
                        ShoppingAddition(
                            product: product.id, amount: try item.double("amount"), unit: unit, reason: reason))
                } else if let text = try item.nonEmpty("text") {
                    additions.append(
                        ShoppingAddition(text: text, amount: try item.double("amount"), unit: unit, reason: reason))
                } else {
                    throw ToolError("items[\(index + 1)]: нужно product или text.")
                }
            } else {
                throw ToolError("items[\(index + 1)] — строка или объект.")
            }
        }
        var ids = try database.addToShopping(additions)
        var recipeTitle: String?
        if let reference = try arguments.nonEmpty("recipe") {
            let id = try recipeID(reference, database)
            let servings = try arguments.int("servings")
            if let servings, !(1...100).contains(servings) { throw ToolError("«servings» — от 1 до 100.") }
            ids += try database.addShortages(ofRecipe: id, servings: servings)
            recipeTitle = try database.recipe(id: id)?.recipe.title
        }
        var forWeek = false
        if arguments.has("week") {
            let start = try week(arguments)
            ids += try database.addMenuShortages(week: start, from: max(Day.today(), start))
            forWeek = true
        }
        guard !additions.isEmpty || recipeTitle != nil || forWeek else {
            throw ToolError("Нужно items, recipe или week.")
        }
        let aisles = try aisleNames(database)
        let entries = try database.shoppingEntries(ids: ids)
        var result: [String: Value] = [
            "added_or_grown": .array(entries.map { ToolOutput.shopping($0, aisles: aisles) })
        ]
        if let recipeTitle, entries.isEmpty {
            result["note"] = .string("Для «\(recipeTitle)» ничего не нужно: всё есть дома или уже в списке.")
        } else if forWeek, entries.isEmpty {
            result["note"] = .string("На меню недели всё есть дома или уже в списке.")
        }
        return .object(result)
    }

    func checkShoppingItems(_ arguments: Arguments) throws -> Value {
        let database = try database()
        let ids = try shoppingIDs(arguments)
        let checked = try arguments.bool("checked") ?? true
        try database.setChecked(checked, items: ids)
        if checked, try arguments.bool("stock") == true {
            let entries = try database.shoppingEntries(ids: ids)
            try database.stockBought(Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.amountInBaseUnit) }))
            return .object(["stocked": .array(entries.map { .string(ShoppingRowText.title(of: $0)) })])
        }
        let aisles = try aisleNames(database)
        return .object([
            "items": .array(try database.shoppingEntries(ids: ids).map { ToolOutput.shopping($0, aisles: aisles) })
        ])
    }

    func removeShoppingItems(_ arguments: Arguments) throws -> Value {
        let database = try database()
        let ids = try shoppingIDs(arguments)
        let entries = try database.shoppingEntries(ids: ids)
        try database.removeShoppingItems(ids)
        return .object(["removed": .array(entries.map { .string(ShoppingRowText.title(of: $0)) })])
    }

    func clearChecked(_ arguments: Arguments) throws -> Value {
        let database = try database()
        var stocked: [Value] = []
        if try arguments.bool("stock") == true {
            let bought = try database.shopping(ShoppingQuery(isChecked: true), limit: 1000).rows
                .filter { $0.item.stockedAt == nil }
            try database.stockBought(Dictionary(uniqueKeysWithValues: bought.map { ($0.id, $0.amountInBaseUnit) }))
            stocked = bought.map { .string(ShoppingRowText.title(of: $0)) }
        }
        let removed = try database.clearChecked()
        return .object(["stocked": .array(stocked), "removed": .int(removed + stocked.count)])
    }

    private func shoppingIDs(_ arguments: Arguments) throws -> Set<ShoppingItem.ID> {
        guard let values = try arguments.array("ids"), !values.isEmpty else { throw ToolError("Нужно «ids».") }
        return Set(
            try values.map { value in
                guard let id = try Arguments(["id": value]).int("id") else { throw ToolError("«ids» — числа.") }
                return Int64(id)
            })
    }

    /// A recipe by id or by its title: the one whose title matches, or the only one the search finds.
    func recipeID(_ reference: String, _ database: AppDatabase) throws -> Recipe.ID {
        if let id = Int64(reference), try database.recipe(id: id) != nil {
            return id
        }
        let found = try database.recipeCards(RecipeQuery(text: reference, sort: [SortTerm(.relevance)]), limit: 5).rows
        if let exact = found.first(where: { SearchText.normalized($0.title) == SearchText.normalized(reference) }) {
            return exact.id
        }
        guard found.count == 1, let only = found.first else {
            let names = found.map { "«\($0.title)» (id \($0.id))" }.joined(separator: ", ")
            throw ToolError(
                found.isEmpty ? "Нет рецепта «\(reference)»." : "«\(reference)»: подходят \(names). Передай id рецепта."
            )
        }
        return only.id
    }
}

/// How the server names a shopping line in its answers: «Молоко — 545 ml».
enum ShoppingRowText {
    static func title(of entry: ShoppingEntry) -> String {
        guard let amount = entry.item.amount else { return entry.name }
        let unit = entry.item.unit ?? .piece
        return "\(entry.name) — \(ToolOutput.text(amount: amount)) \(unit.symbol)"
    }
}
