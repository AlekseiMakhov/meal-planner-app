import Foundation
import MCP
import MealCore
import MealStore

extension MealTools {
    static let productTools: [Tool] = [
        Tool(
            name: "search_products", title: "Продукты",
            description:
                "Поиск по базе продуктов: название и синонимы в любой форме слова («молока» найдёт «Молоко 3,2%»), фильтры и сортировка — как на экране «Продукты». КБЖУ — на 100 г.",
            inputSchema: schema(
                [
                    "query": string("Слова из названия или синонима; пусто — все продукты."),
                    "aisles": strings("Только эти отделы (названия из list_aisles)."),
                    "staple": boolean("true — только «обычно есть дома» (соль, масло, специи), false — кроме них."),
                    "nutrition": choice(
                        ["missing", "needs_review", "complete"],
                        "missing — КБЖУ заполнено не полностью, needs_review — помечены «проверить», complete — заполнено."
                    ),
                    "kcal_min": number("Калорийность на 100 г от."),
                    "kcal_max": number("Калорийность на 100 г до."),
                    "used_in_recipes": boolean("true — продукты из рецептов, false — ни в одном рецепте."),
                    "sort": choice(
                        ["name", "aisle", "kcal", "protein", "fat", "carbs", "created", "recipe_count", "relevance"],
                        "Порядок; по умолчанию name, с query — relevance."),
                ].merging(page) { first, _ in first }),
            annotations: readOnly),
        Tool(
            name: "get_product", title: "Продукт",
            description: "Продукт по id или по точному названию или синониму.",
            inputSchema: schema(["id": integer("Id продукта."), "name": string("Название или синоним.")]),
            annotations: readOnly),
        Tool(
            name: "upsert_product", title: "Создать или изменить продукт",
            description: """
                Создаёт продукт или меняет существующий: по id, иначе по точному названию или синониму. Меняются только переданные поля. \
                КБЖУ — на 100 г съедобной части; заполняй все четыре значения сразу. Если КБЖУ передано, а source нет, источником станет claude. \
                Единицы: base_unit — в чём продукт хранится дома (g, ml, pcs); grams_per_piece — вес одной штуки без кожуры и скорлупы; \
                density — граммов в миллилитре, для ложек и стаканов; units — вес именованных единиц: clove (зубчик), bunch (пучок), slice, \
                sprig, leaf, head, can (банка без жидкости), pack, handful.
                """,
            inputSchema: schema([
                "id": integer("Id продукта, если он известен."),
                "name": string(
                    "Название в именительном падеже, с большой буквы: «Фета», «Молоко 2,5%». С id — новое название."),
                "aliases": strings("Синонимы и формы, которые встречаются в рецептах; заменяют прежние."),
                "add_aliases": strings("Синонимы, которые добавить к прежним."),
                "aisle": string("Отдел из list_aisles."),
                "kcal": number("Ккал на 100 г."),
                "protein": number("Белки, г на 100 г."),
                "fat": number("Жиры, г на 100 г."),
                "carbs": number("Углеводы, г на 100 г."),
                "base_unit": choice(["g", "ml", "pcs"], "В чём продукт хранится и покупается."),
                "grams_per_piece": number("Вес одной штуки, г."),
                "density": number("Граммов в миллилитре."),
                "units": .object([
                    "type": "object", "additionalProperties": ["type": "number"],
                    "description": "Граммы одной единицы: {\"clove\": 5}. 0 убирает единицу.",
                ]),
                "staple": boolean("Обычно есть дома: соль, масло, специи — важно, есть или нет, а не граммы."),
                "source": choice(
                    ["usda", "label", "reference", "manual", "claude"],
                    "Откуда КБЖУ: usda, label — с упаковки, reference — справочник, manual, claude."),
                "source_note": string("Откуда взяты значения: сайт, бренд, номер записи."),
                "needs_review": boolean("Пометка «проверить»: значения приблизительные или сомнительные."),
            ]),
            annotations: idempotent),
        Tool(
            name: "merge_products", title: "Объединить дубли",
            description:
                "Объединяет дубль с продуктом, который остаётся: название и синонимы дубля станут синонимами, недостающие КБЖУ и единицы возьмутся из дубля, рецепты перейдут на оставшийся продукт. Дубль удаляется.",
            inputSchema: schema(
                [
                    "duplicate": string("Дубль: id или название."),
                    "keep": string("Продукт, который остаётся: id или название."),
                ], required: ["duplicate", "keep"]),
            annotations: destructive),
    ]

    func searchProducts(_ arguments: Arguments) throws -> Value {
        let database = try database()
        var query = ProductQuery(text: try arguments.string("query") ?? "")
        if let names = try arguments.strings("aisles") {
            query.aisleIDs = Set(try names.map { name throws in try aisle(name, database).id })
        }
        query.isStaple = try arguments.bool("staple")
        if let nutrition = try arguments.string("nutrition") {
            guard
                let state = ProductQuery.NutritionState(
                    rawValue: nutrition == "needs_review" ? "needsReview" : nutrition)
            else { throw ToolError("«nutrition» — missing, needs_review или complete.") }
            query.nutrition = state
        }
        query.kcal = ValueRange(min: try arguments.double("kcal_min"), max: try arguments.double("kcal_max"))
        query.isUsedInRecipes = try arguments.bool("used_in_recipes")
        let keys: [String: ProductQuery.SortKey] = [
            "name": .name, "aisle": .aisle, "kcal": .kcal, "protein": .protein, "fat": .fat, "carbs": .carbs,
            "created": .createdAt, "recipe_count": .recipeCount, "relevance": .relevance,
        ]
        let sort = try arguments.string("sort") ?? (query.text.isEmpty ? "name" : "relevance")
        guard let key = keys[sort] else { throw ToolError("Нет сортировки «\(sort)».") }
        query.sort = [SortTerm(key, try arguments.bool("descending") == true ? .descending : .ascending)]

        let offset = try arguments.offset()
        let page = try database.products(query, limit: try arguments.limit(), offset: offset)
        let aisles = try aisleNames(database)
        return .object([
            "total": .int(page.total),
            "products": .array(page.rows.map { ToolOutput.product($0, aisles: aisles) }),
            "next_cursor": offset + page.rows.count < page.total ? .string(String(offset + page.rows.count)) : .null,
        ])
    }

    func getProduct(_ arguments: Arguments) throws -> Value {
        let database = try database()
        let product = try existingProduct(arguments, database)
        let recipes = try database.recipeCount(of: product.id)
        guard case .object(var object) = ToolOutput.product(product, aisles: try aisleNames(database)) else {
            return .null
        }
        object["recipe_count"] = .int(recipes)
        return .object(object)
    }

    func upsertProduct(_ arguments: Arguments) throws -> Value {
        let database = try database()
        var product: Product
        var created = false
        if arguments.has("id") {
            product = try existingProduct(arguments, database)
            if let name = try arguments.string("name"), !name.isEmpty {
                product.name = name
            }
        } else {
            let name = try arguments.required("name")
            if let existing = try database.product(named: name) {
                product = existing
            } else {
                product = try database.newProduct(named: name)
                created = true
            }
        }
        do {
            try apply(arguments, to: &product, database)
            product = try database.save(product)
        } catch {
            if created { try? database.deleteProduct(id: product.id) }
            throw error
        }
        guard case .object(var object) = ToolOutput.product(product, aisles: try aisleNames(database)) else {
            return .null
        }
        object["created"] = .bool(created)
        if let nutrition = product.nutrition, !nutrition.caloriesMatchMacros, product.nutritionSource != .usda {
            object["warning"] = .string(
                "По белкам, жирам и углеводам выходит около \(Int(nutrition.kcalFromMacros.rounded())) ккал, а указано \(Int(nutrition.kcal.rounded())): проверь значения."
            )
        }
        return .object(object)
    }

    private func apply(_ arguments: Arguments, to product: inout Product, _ database: AppDatabase) throws {
        if let aliases = try arguments.strings("aliases") {
            product.aliases = aliases
        }
        if let more = try arguments.strings("add_aliases") {
            product.aliases += more
        }
        if let name = try arguments.string("aisle") {
            product.aisleID = name.isEmpty ? nil : try aisle(name, database).id
        }
        let nutrition = ["kcal", "protein", "fat", "carbs"]
        if nutrition.contains(where: arguments.has) {
            product.kcal = try arguments.double("kcal") ?? product.kcal
            product.protein = try arguments.double("protein") ?? product.protein
            product.fat = try arguments.double("fat") ?? product.fat
            product.carbs = try arguments.double("carbs") ?? product.carbs
            if !arguments.has("source") {
                product.nutritionSource = .claude
                product.sourceNote = nil
            }
        }
        if let base = try arguments.string("base_unit") {
            guard let unit = BaseUnit(rawValue: base) else { throw ToolError("«base_unit» — g, ml или pcs.") }
            product.baseUnit = unit
        }
        if arguments.has("grams_per_piece") {
            product.gramsPerPiece = try arguments.double("grams_per_piece")
        }
        if arguments.has("density") {
            product.density = try arguments.double("density")
        }
        if let units = try arguments.object("units") {
            for (key, value) in units {
                guard let unit = MeasureUnit(parsing: key), unit.kind == .named else {
                    throw ToolError(
                        "Единица «\(key)» не подходит для units: clove, bunch, slice, sprig, leaf, head, can, pack, handful."
                    )
                }
                let grams = try Arguments(["value": value]).double("value")
                product.namedUnits[unit] = (grams ?? 0) > 0 ? grams : nil
            }
        }
        if let staple = try arguments.bool("staple") {
            product.isStaple = staple
        }
        if let source = try arguments.string("source") {
            guard let value = NutritionSource(rawValue: source) else { throw ToolError("Нет источника «\(source)».") }
            product.nutritionSource = value
        }
        if arguments.has("source_note") {
            product.sourceNote = try arguments.nonEmpty("source_note")
        }
        if let review = try arguments.bool("needs_review") {
            product.needsReview = review
        }
    }

    func mergeProducts(_ arguments: Arguments) throws -> Value {
        let database = try database()
        let duplicate = try product(reference: try arguments.required("duplicate"), database)
        let kept = try product(reference: try arguments.required("keep"), database)
        let merged = try database.mergeProduct(duplicate.id, into: kept.id)
        return ToolOutput.product(merged, aisles: try aisleNames(database))
    }

    // MARK: - Lookups

    func aisleNames(_ database: AppDatabase) throws -> [Int64: String] {
        Dictionary(uniqueKeysWithValues: try database.aisles().map { ($0.id, $0.name) })
    }

    func aisle(_ name: String, _ database: AppDatabase) throws -> Aisle {
        guard let aisle = try database.aisle(named: name) else {
            throw ToolError(
                "Нет отдела «\(name)». Отделы: \(try database.aisles().map(\.name).joined(separator: ", ")).")
        }
        return aisle
    }

    private func existingProduct(_ arguments: Arguments, _ database: AppDatabase) throws -> Product {
        if let id = try arguments.int("id") {
            guard let product = try database.product(id: Int64(id)) else { throw ToolError("Нет продукта с id \(id).") }
            return product
        }
        return try product(reference: try arguments.required("name"), database)
    }

    /// A product by id («12») or by its exact name or alias.
    func product(reference: String, _ database: AppDatabase) throws -> Product {
        if let id = Int64(reference), let product = try database.product(id: id) {
            return product
        }
        guard let product = try database.product(named: reference) else {
            throw ToolError("Нет продукта «\(reference)». Найди его через search_products.")
        }
        return product
    }
}
