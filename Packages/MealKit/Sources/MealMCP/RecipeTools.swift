import Foundation
import MCP
import MealCore
import MealStore

extension MealTools {
    private static let ingredientItem: Value = .object([
        "description": """
        Строка ингредиента, как в рецепте: «40 г феты», «2–3 зубчика чеснока», «соль по вкусу» — или объект. \
        Строка годится, когда продукт уже есть в базе: название ищется в любой форме слова. Для нового продукта нужен объект: \
        из name в именительном падеже будет создан продукт.
        """,
        "anyOf": [
            ["type": "string"],
            [
                "type": "object", "additionalProperties": false,
                "properties": [
                    "name": [
                        "type": "string",
                        "description":
                            "Продукт в именительном падеже: «Фета», «Молоко 3,2%»; нет такого — будет создан.",
                    ],
                    "product_id": ["type": "integer", "description": "Id продукта из search_products, вместо name."],
                    "amount": ["type": "number", "description": "Количество; без него — «по вкусу» или «для жарки»."],
                    "amount_max": ["type": "number", "description": "Верхняя граница: 3 для «2–3 зубчика»."],
                    "unit": [
                        "type": "string",
                        "description":
                            "Единица: g, kg, ml, l, tsp, tbsp, cup (250 мл), pcs, clove, bunch, slice, sprig, leaf, head, can, pack, handful, pinch, to-taste — или по-русски: «г», «ст. л.», «зубчик».",
                    ],
                    "note": ["type": "string", "description": "«мелко нарезать», «для жарки», «крупный»."],
                    "optional": ["type": "boolean", "description": "По желанию."],
                    "group": ["type": "string", "description": "Подзаголовок, под которым строка стоит: «Для соуса»."],
                ],
            ],
        ],
    ])

    /// What `unset` in update_recipe can clear.
    private static let clearable = [
        "image", "video_url", "source_url", "notes", "prep_minutes", "cook_minutes", "yield_grams",
        "nutrition_per_100g",
    ]

    private static let recipeFields: [String: Value] = [
        "title": string("Название рецепта."),
        "servings": integer("Сколько порций дают ингредиенты; по умолчанию 2."),
        "categories": strings("Категории по названию; несуществующие будут созданы. Заменяют прежние."),
        "meal_types": strings("На какие приёмы пищи подходит: завтрак, обед, ужин, перекус. Заменяют прежние."),
        "ingredients": .object([
            "type": "array", "items": ingredientItem,
            "description": "Ингредиенты по порядку рецепта; заменяют прежние.",
        ]),
        "steps": strings("Шаги приготовления по порядку, без номеров; заменяют прежние."),
        "notes": string("Заметки: советы, хранение, подача."),
        "source_url": string("Ссылка на источник рецепта."),
        "video_url": string("Ссылка на видео (YouTube, Rutube, VK Видео) или код <iframe>."),
        "image_url": string("Ссылка на фото блюда: сервер скачает его."),
        "prep_minutes": integer("Подготовка, минут."),
        "cook_minutes": integer("Готовка, минут."),
        "yield_grams": number("Вес готового блюда, г: с ним калорийность на 100 г считается по готовому блюду."),
        "nutrition_per_100g": .object([
            "type": "object", "additionalProperties": false,
            "description": "КБЖУ на 100 г, если его даёт источник: заменяет расчёт по ингредиентам.",
            "properties": [
                "kcal": ["type": "number"], "protein": ["type": "number"], "fat": ["type": "number"],
                "carbs": ["type": "number"],
            ],
            "required": ["kcal", "protein", "fat", "carbs"],
        ]),
        "favorite": boolean("В избранном."),
    ]

    static let recipeTools: [Tool] = [
        Tool(
            name: "search_recipes", title: "Рецепты",
            description:
                "Поиск рецептов: по названию, продуктам, шагам и заметкам в любой форме слова; фильтры и сортировка — как в приложении. КБЖУ и фильтры по нему — на порцию. Рецепты из корзины не попадают.",
            inputSchema: schema(
                [
                    "query": string("Слова из названия, продуктов, шагов или заметок."),
                    "categories": strings("Рецепты из любой из этих категорий."),
                    "meal_types": strings("Подходящие на любой из этих приёмов пищи."),
                    "with_products": strings("Рецепты со всеми этими продуктами."),
                    "without_products": strings("Рецепты без этих продуктов: «молоко»."),
                    "kcal_per_serving_min": number("Ккал на порцию от."),
                    "kcal_per_serving_max": number("Ккал на порцию до."),
                    "protein_min": number("Белки на порцию от, г."),
                    "protein_max": number("Белки на порцию до, г."),
                    "fat_min": number("Жиры на порцию от, г."),
                    "fat_max": number("Жиры на порцию до, г."),
                    "carbs_min": number("Углеводы на порцию от, г."),
                    "carbs_max": number("Углеводы на порцию до, г."),
                    "max_minutes": integer("Подготовка и готовка вместе — не дольше, минут."),
                    "favorite": boolean("Только избранные (true) или только не избранные (false)."),
                    "has_photo": boolean("С фото или без."),
                    "has_video": boolean("С видео или без."),
                    "nutrition_incomplete": boolean(
                        "true — КБЖУ посчитано не полностью: у продуктов нет КБЖУ или пересчёта в граммы."),
                    "sort": choice(
                        [
                            "title", "kcal_per_100g", "kcal_per_serving", "protein", "fat", "carbs", "total_time",
                            "created",
                            "updated", "relevance",
                        ], "Порядок; по умолчанию title, с query — relevance."),
                ].merging(page) { first, _ in first }),
            annotations: readOnly),
        Tool(
            name: "get_recipe", title: "Рецепт",
            description:
                "Рецепт целиком: ингредиенты с граммами, шаги, КБЖУ на 100 г и на порцию и чего не хватает для полного расчёта.",
            inputSchema: schema(
                [
                    "id": integer("Id рецепта."),
                    "servings": integer("Пересчитать количества ингредиентов на столько порций."),
                ], required: ["id"]),
            annotations: readOnly),
        Tool(
            name: "create_recipe", title: "Новый рецепт",
            description: """
                Создаёт рецепт. Продукты ингредиентов ищутся в базе по названию и синонимам; новые создаются без КБЖУ и перечисляются \
                в created_products — заполни их КБЖУ через upsert_product. matched_by_search — строки, для которых продукт найден \
                поиском, а не по точному названию: проверь их. Если строка подходит к нескольким продуктам, рецепт не создаётся, \
                а в ответе — варианты: уточни name или передай product_id.
                """,
            inputSchema: schema(recipeFields, required: ["title"]),
            annotations: changes),
        Tool(
            name: "update_recipe", title: "Изменить рецепт",
            description:
                "Меняет переданные поля рецепта; ingredients, steps, categories и meal_types заменяются целиком — возьми текущие через get_recipe. Продукты ингредиентов — как в create_recipe.",
            inputSchema: schema(
                recipeFields.merging([
                    "id": integer("Id рецепта."),
                    "unset": .object([
                        "type": "array", "items": ["type": "string", "enum": .array(clearable.map(Value.string))],
                        "description": "Поля, которые очистить: image — убрать фото.",
                    ]),
                ]) { first, _ in first },
                required: ["id"]),
            annotations: idempotent),
        Tool(
            name: "delete_recipe", title: "Удалить рецепт",
            description: "Убирает рецепт в корзину: в приложении его можно восстановить в течение 30 дней.",
            inputSchema: schema(["id": integer("Id рецепта.")], required: ["id"]),
            annotations: destructive),
        Tool(
            name: "set_recipe_image", title: "Фото рецепта",
            description: "Скачивает фото по ссылке и ставит его рецепту; прежнее фото удаляется.",
            inputSchema: schema(
                ["id": integer("Id рецепта."), "url": string("Ссылка на картинку.")], required: ["id", "url"]),
            annotations: changes),
    ]

    // MARK: - Reading

    func searchRecipes(_ arguments: Arguments) throws -> Value {
        let database = try database()
        var query = RecipeQuery(text: try arguments.string("query") ?? "")
        if let names = try arguments.strings("categories") {
            query.categoryIDs = Set(try names.map { try category(reference: $0, database).id })
        }
        if let names = try arguments.strings("meal_types") {
            query.mealTypeIDs = Set(try names.map { try mealType($0, database).id })
        }
        if let names = try arguments.strings("with_products") {
            query.withProducts = Set(try names.map { try oneProduct($0, database).id })
        }
        if let names = try arguments.strings("without_products") {
            query.withoutProducts = Set(try names.map { try oneProduct($0, database).id })
        }
        query.kcalPerServing = try range(arguments, "kcal_per_serving")
        query.protein = try range(arguments, "protein")
        query.fat = try range(arguments, "fat")
        query.carbs = try range(arguments, "carbs")
        query.maxMinutes = try arguments.int("max_minutes")
        query.isFavorite = try arguments.bool("favorite")
        query.hasPhoto = try arguments.bool("has_photo")
        query.hasVideo = try arguments.bool("has_video")
        query.nutritionIncomplete = try arguments.bool("nutrition_incomplete")
        let keys: [String: RecipeQuery.SortKey] = [
            "title": .title, "kcal_per_100g": .kcalPer100, "kcal_per_serving": .kcalPerServing, "protein": .protein,
            "fat": .fat, "carbs": .carbs, "total_time": .totalTime, "created": .createdAt, "updated": .updatedAt,
            "relevance": .relevance,
        ]
        let sort = try arguments.string("sort") ?? (query.text.isEmpty ? "title" : "relevance")
        guard let key = keys[sort] else { throw ToolError("Нет сортировки «\(sort)».") }
        query.sort = [SortTerm(key, try arguments.bool("descending") == true ? .descending : .ascending)]

        let offset = try arguments.offset()
        let page = try database.recipeCards(query, limit: try arguments.limit(), offset: offset)
        let categories = try categoryNames(database)
        return .object([
            "total": .int(page.total),
            "recipes": .array(page.rows.map { ToolOutput.recipeCard($0, categories: categories) }),
            "next_cursor": offset + page.rows.count < page.total ? .string(String(offset + page.rows.count)) : .null,
        ])
    }

    func getRecipe(_ arguments: Arguments) throws -> Value {
        let database = try database()
        let details = try recipe(arguments, database)
        let servings = try arguments.int("servings")
        if let servings, !(1...100).contains(servings) {
            throw ToolError("«servings» — от 1 до 100.")
        }
        return ToolOutput.recipe(
            details, servings: servings, categories: try categoryNames(database), mealTypes: try mealTypeNames(database)
        )
    }

    // MARK: - Changing

    func createRecipe(_ arguments: Arguments) async throws -> Value {
        let database = try database()
        var draft = RecipeDetails(recipe: Recipe(id: 0, title: try arguments.required("title")))
        let plan = try prepare(arguments, into: &draft, database)
        return try await commit(plan, draft, arguments, database) { try database.newRecipe(from: $0) }
    }

    func updateRecipe(_ arguments: Arguments) async throws -> Value {
        let database = try database()
        var draft = try recipe(arguments, database)
        if let title = try arguments.string("title") {
            draft.recipe.title = title
        }
        try unset(arguments, in: &draft)
        let plan = try prepare(arguments, into: &draft, database)
        return try await commit(plan, draft, arguments, database) { try database.save($0) }
    }

    func deleteRecipe(_ arguments: Arguments) throws -> Value {
        let database = try database()
        let details = try recipe(arguments, database)
        try database.moveRecipeToTrash(id: details.recipe.id)
        return .object([
            "moved_to_trash": .string(details.recipe.title),
            "restore": "В приложении: Рецепты → Ещё → Корзина…, в течение 30 дней.",
        ])
    }

    func setRecipeImage(_ arguments: Arguments) async throws -> Value {
        let database = try database()
        var details = try recipe(arguments, database)
        guard let url = URL(string: try arguments.required("url")) else {
            throw ToolError("«url» — ссылка на картинку.")
        }
        let photo = try await database.images.download(url)
        details.recipe.photo = photo
        do {
            details = try database.save(details)
        } catch {
            database.images.delete(photo)
            throw error
        }
        return .object([
            "id": ToolOutput.id(details.recipe.id), "title": .string(details.recipe.title), "has_photo": true,
        ])
    }

    // MARK: - Preparing a recipe

    /// What a call needs before its recipe can be saved. Nothing is written until every line has a product, so
    /// a call with one unclear line changes nothing.
    struct RecipePlan {
        /// The ingredient lines when the call gives them; the lines of new products have no product yet.
        var ingredients: [RecipeIngredient]?
        /// The products to create: a line's index and the product's name.
        var newProducts: [(line: Int, name: String)] = []
        var newCategories: [String] = []
        /// Lines whose product was found by search rather than by its exact name: «феты» → «Сыр фета».
        var matchedBySearch: [String] = []

        func make(in database: AppDatabase, into made: inout MadeOnTheWay) throws {
            for (_, name) in newProducts where made.products[SearchText.normalized(name)] == nil {
                made.products[SearchText.normalized(name)] = try database.newProduct(named: name)
            }
            for name in newCategories {
                made.categories.append(try database.newCategory(named: name))
            }
        }

        func lines(using products: [String: Product]) -> [RecipeIngredient]? {
            guard var lines = ingredients else { return nil }
            for (line, name) in newProducts {
                if let product = products[SearchText.normalized(name)] {
                    lines[line].productID = product.id
                }
            }
            return lines
        }
    }

    /// The products and categories a call created: reported back, and removed again when the recipe is not saved.
    struct MadeOnTheWay {
        var products: [String: Product] = [:]
        var categories: [RecipeCategory] = []

        func undo(in database: AppDatabase) {
            for product in products.values {
                try? database.deleteProduct(id: product.id)
            }
            for category in categories {
                try? database.deleteCategory(id: category.id)
            }
        }
    }

    /// Applies the call's fields to the draft and finds the products of its ingredients; throws, listing every
    /// problem, when the recipe cannot be saved.
    private func prepare(_ arguments: Arguments, into draft: inout RecipeDetails, _ database: AppDatabase) throws
        -> RecipePlan
    {
        var plan = RecipePlan()
        if let servings = try arguments.int("servings") {
            draft.recipe.servings = servings
        }
        if let notes = try arguments.string("notes") { draft.recipe.notes = notes }
        if let link = try arguments.nonEmpty("source_url") { draft.recipe.sourceURL = link }
        if let link = try arguments.nonEmpty("video_url") { draft.recipe.videoURL = link }
        if let minutes = try arguments.int("prep_minutes") { draft.recipe.prepMinutes = minutes }
        if let minutes = try arguments.int("cook_minutes") { draft.recipe.cookMinutes = minutes }
        if let grams = try arguments.double("yield_grams") { draft.recipe.yieldGrams = grams }
        if let favorite = try arguments.bool("favorite") { draft.recipe.isFavorite = favorite }
        if let nutrition = try arguments.object("nutrition_per_100g") {
            let values = Arguments(nutrition)
            guard let kcal = try values.double("kcal"), let protein = try values.double("protein"),
                let fat = try values.double("fat"), let carbs = try values.double("carbs")
            else { throw ToolError("«nutrition_per_100g» — все четыре: kcal, protein, fat, carbs.") }
            draft.recipe.nutritionOverride = Nutrition(kcal: kcal, protein: protein, fat: fat, carbs: carbs)
        }
        if let steps = try arguments.strings("steps") {
            draft.steps = steps.map { RecipeStep(text: $0) }
        }
        if let names = try arguments.strings("categories") {
            draft.categoryIDs = []
            let categories = try database.categories()
            for name in names {
                let key = SearchText.normalized(name)
                if let category = categories.first(where: { SearchText.normalized($0.name) == key }) {
                    draft.categoryIDs.append(category.id)
                } else if !plan.newCategories.contains(where: { SearchText.normalized($0) == key }) {
                    plan.newCategories.append(name)
                }
            }
        }
        if let names = try arguments.strings("meal_types") {
            draft.mealTypeIDs = Set(try names.map { try mealType($0, database).id })
        }
        if let items = try arguments.array("ingredients") {
            try resolveIngredients(items, into: &plan, database)
            draft.ingredients = plan.ingredients ?? []
        }
        if let problem = draft.problems.first {
            throw ToolError(problem)
        }
        return plan
    }

    private func resolveIngredients(_ items: [Value], into plan: inout RecipePlan, _ database: AppDatabase) throws {
        var lines: [RecipeIngredient] = []
        var problems: [String] = []
        func found(_ product: Product, for given: String, _ line: RecipeIngredient) {
            var line = line
            line.productID = product.id
            lines.append(line)
            let key = SearchText.normalized(given)
            if SearchText.normalized(product.name) != key,
                !product.aliases.contains(where: { SearchText.normalized($0) == key })
            {
                plan.matchedBySearch.append("«\(given)» → «\(product.name)»")
            }
        }
        for (index, item) in items.enumerated() {
            if let text = item.stringValue {
                let parsed = IngredientParser.parse(text)
                if parsed.isEmpty {
                    problems.append("Строка \(index + 1) «\(text)»: в ней нет продукта.")
                }
                for part in parsed {
                    let line = RecipeIngredient(
                        productID: 0, amount: part.amount, amountMax: part.amountMax, unit: part.unit, note: part.note,
                        isOptional: part.isOptional)
                    switch try database.matchProduct(named: part.name) {
                    case .found(let product):
                        found(product, for: part.name, line)
                    case .ambiguous(let candidates):
                        problems.append(ambiguity(part.name, candidates))
                    case .none:
                        problems.append(
                            "«\(text)»: продукта «\(part.name)» в базе нет. Передай эту строку объектом, где name — продукт в именительном падеже, и он будет создан."
                        )
                    }
                }
            } else if let object = item.objectValue {
                let values = Arguments(object)
                var line = RecipeIngredient(
                    productID: 0, amount: try values.double("amount"), amountMax: try values.double("amount_max"),
                    note: try values.nonEmpty("note"), group: try values.nonEmpty("group"),
                    isOptional: try values.bool("optional") ?? false)
                if let unit = try values.nonEmpty("unit") {
                    guard let parsed = MeasureUnit(parsing: unit) else {
                        problems.append("Ингредиент \(index + 1): нет единицы «\(unit)».")
                        continue
                    }
                    line.unit = parsed
                }
                if let id = try values.int("product_id") {
                    guard let product = try database.product(id: Int64(id)) else {
                        problems.append("Ингредиент \(index + 1): нет продукта с id \(id).")
                        continue
                    }
                    line.productID = product.id
                    lines.append(line)
                } else if let name = try values.nonEmpty("name") {
                    switch try database.matchProduct(named: name) {
                    case .found(let product):
                        found(product, for: name, line)
                    case .ambiguous(let candidates):
                        problems.append(ambiguity(name, candidates))
                    case .none:
                        plan.newProducts.append((lines.count, name.prefix(1).uppercased() + name.dropFirst()))
                        lines.append(line)
                    }
                } else {
                    problems.append("Ингредиент \(index + 1): нужно name или product_id.")
                }
            } else {
                problems.append("Ингредиент \(index + 1): строка или объект.")
            }
        }
        if !problems.isEmpty {
            throw ToolError("Рецепт не сохранён, ничего не изменилось.\n" + problems.joined(separator: "\n"))
        }
        plan.ingredients = lines
    }

    private func ambiguity(_ name: String, _ candidates: [Product]) -> String {
        let names = candidates.map { "«\($0.name)» (id \($0.id))" }.joined(separator: ", ")
        return
            "«\(name)»: подходят \(names). Передай product_id одного из них или уточни name; нужен отдельный продукт — создай его через upsert_product."
    }

    private func unset(_ arguments: Arguments, in draft: inout RecipeDetails) throws {
        for field in try arguments.strings("unset") ?? [] {
            switch field {
            case "image": draft.recipe.photo = nil
            case "video_url": draft.recipe.videoURL = nil
            case "source_url": draft.recipe.sourceURL = nil
            case "notes": draft.recipe.notes = ""
            case "prep_minutes": draft.recipe.prepMinutes = nil
            case "cook_minutes": draft.recipe.cookMinutes = nil
            case "yield_grams": draft.recipe.yieldGrams = nil
            case "nutrition_per_100g": draft.recipe.nutritionOverride = nil
            default:
                throw ToolError("«unset»: нет поля «\(field)». Можно: \(Self.clearable.joined(separator: ", ")).")
            }
        }
    }

    /// Downloads the photo, creates the products and categories the plan needs and saves the recipe. A failure
    /// takes back what was made on the way.
    private func commit(
        _ plan: RecipePlan, _ draft: RecipeDetails, _ arguments: Arguments, _ database: AppDatabase,
        save: (RecipeDetails) throws -> RecipeDetails
    ) async throws -> Value {
        var draft = draft
        let image = try await downloadImage(arguments, database)
        if let photo = image.photo {
            draft.recipe.photo = photo
        }
        var made = MadeOnTheWay()
        let saved: RecipeDetails
        do {
            try plan.make(in: database, into: &made)
            draft.categoryIDs += made.categories.map(\.id)
            if let lines = plan.lines(using: made.products) {
                draft.ingredients = lines
            }
            saved = try save(draft)
        } catch {
            if let photo = image.photo {
                database.images.delete(photo)
            }
            made.undo(in: database)
            throw error
        }
        guard
            case .object(var object) = ToolOutput.recipe(
                saved, servings: nil, categories: try categoryNames(database), mealTypes: try mealTypeNames(database))
        else { return .null }
        object["created_products"] = .array(
            made.products.values.sorted { $0.name < $1.name }.map {
                .object(["id": ToolOutput.id($0.id), "name": .string($0.name)])
            })
        if !made.categories.isEmpty {
            object["created_categories"] = .array(made.categories.map { .string($0.name) })
        }
        if !plan.matchedBySearch.isEmpty {
            object["matched_by_search"] = .array(plan.matchedBySearch.map(Value.string))
        }
        if let problem = image.problem {
            object["image_problem"] = .string(problem)
        }
        return .object(object)
    }

    /// The photo the call links to, saved; a failed download leaves the recipe without it and says why.
    private func downloadImage(_ arguments: Arguments, _ database: AppDatabase) async throws -> (
        photo: String?, problem: String?
    ) {
        guard let link = try arguments.nonEmpty("image_url") else { return (nil, nil) }
        guard let url = URL(string: link) else { return (nil, "Фото не скачано: «\(link)» — не ссылка.") }
        do {
            return (try await database.images.download(url), nil)
        } catch let error as StoreError {
            return (nil, "Фото не скачано: \(error.message) Другую ссылку можно дать через set_recipe_image.")
        } catch {
            return (
                nil, "Фото не скачано: \(error.localizedDescription) Другую ссылку можно дать через set_recipe_image."
            )
        }
    }

    // MARK: - Lookups

    private func recipe(_ arguments: Arguments, _ database: AppDatabase) throws -> RecipeDetails {
        guard let id = try arguments.int("id") else { throw ToolError("Нужно «id» рецепта.") }
        guard let details = try database.recipe(id: Int64(id)) else { throw ToolError("Нет рецепта с id \(id).") }
        return details
    }

    /// The one product a filter means; several or none are a mistake to fix.
    private func oneProduct(_ name: String, _ database: AppDatabase) throws -> Product {
        switch try database.matchProduct(named: name) {
        case .found(let product): return product
        case .ambiguous(let candidates): throw ToolError(ambiguity(name, candidates))
        case .none: throw ToolError("Нет продукта «\(name)». Найди его через search_products.")
        }
    }

    private func range(_ arguments: Arguments, _ prefix: String) throws -> ValueRange {
        ValueRange(min: try arguments.double("\(prefix)_min"), max: try arguments.double("\(prefix)_max"))
    }
}
