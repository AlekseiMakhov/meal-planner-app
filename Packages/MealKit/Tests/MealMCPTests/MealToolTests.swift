import Foundation
import MCP
import MealCore
import MealStore
import Testing

@testable import MealMCP

struct ProductToolTests {
    @Test func searchFindsAnyFormOfTheWordAndReadsInPages() async throws {
        let fixture = try ToolFixture()
        let found = try await fixture.call("search_products", ["query": "сулугуни"])
        #expect(found["products"]?.each("name") == ["Сыр сулугуни"])
        let milk = try await fixture.call("search_products", ["query": "молока", "sort": "name"])
        #expect(milk["products"]?.each("name").contains("Молоко 3,2%") == true)

        let first = try await fixture.call("search_products", ["query": "сыр", "limit": 2])
        let total = try #require(first["total"]?.intValue)
        #expect(total > 5)
        let names = try #require(first["products"]?.each("name"))
        #expect(names.count == 2)
        let cursor = try #require(first["next_cursor"]?.stringValue)
        let second = try await fixture.call("search_products", ["query": "сыр", "limit": 2, "cursor": .string(cursor)])
        let more = try #require(second["products"]?.each("name"))
        #expect(more.count == 2)
        #expect(Set(names).isDisjoint(with: more))

        let last = try await fixture.call("search_products", ["query": "сыр", "limit": 100])
        #expect(last["next_cursor"] == .null)
    }

    @Test func upsertCreatesThenChangesOnlyWhatIsGiven() async throws {
        let fixture = try ToolFixture()
        let created = try await fixture.call(
            "upsert_product",
            [
                "name": "Паста мисо", "aisle": "Масла, соусы и уксус", "kcal": 199, "protein": 12, "fat": 6,
                "carbs": 26,
                "density": 1.2, "add_aliases": ["мисо"],
            ])
        #expect(created["created"]?.boolValue == true)
        #expect(created["source"]?.stringValue == "claude")
        #expect(created["aliases"] == .array(["мисо"]))

        let changed = try await fixture.call("upsert_product", ["name": "мисо", "needs_review": true])
        #expect(changed["created"]?.boolValue == false)
        #expect(changed["id"] == created["id"])
        #expect(changed["kcal"]?.intValue == 199)
        #expect(changed["needs_review"]?.boolValue == true)
    }

    @Test func upsertRefusesBadValuesAndLeavesNoHalfMadeProduct() async throws {
        let fixture = try ToolFixture()
        let message = await fixture.failure(
            "upsert_product", ["name": "Странный продукт", "kcal": 50, "protein": 120, "fat": 0, "carbs": 0])
        #expect(message.contains("Белки"))
        #expect(try fixture.database.product(named: "Странный продукт") == nil)
        #expect(await fixture.failure("upsert_product", ["name": "Чай", "aisle": "Космос"]).contains("Отделы:"))

        let doubtful = try await fixture.call(
            "upsert_product", ["name": "Протеиновый батончик", "kcal": 50, "protein": 30, "fat": 10, "carbs": 30])
        #expect(doubtful["warning"]?.stringValue?.contains("около 330 ккал") == true)
    }

    @Test func mergeMovesRecipesToTheProductThatStays() async throws {
        let fixture = try ToolFixture()
        let duplicate = try await fixture.call("upsert_product", ["name": "Яички куриные"])
        _ = try await fixture.call(
            "create_recipe", ["title": "Яичница", "ingredients": [["product_id": duplicate["id"]!, "amount": 2]]])
        let merged = try await fixture.call(
            "merge_products", ["duplicate": "Яички куриные", "keep": "Яйцо куриное"])
        #expect(merged["aliases"]?.arrayValue?.contains("Яички куриные") == true)
        let product = try await fixture.call("get_product", ["name": "Яйцо куриное"])
        #expect(product["recipe_count"]?.intValue == 1)
    }
}

struct CategoryToolTests {
    @Test func categoriesAreCreatedMovedAndDeleted() async throws {
        let fixture = try ToolFixture()
        _ = try await fixture.call("create_category", ["name": "Завтраки", "color": "yellow"])
        _ = try await fixture.call("create_category", ["name": "Супы"])
        let moved = try await fixture.call("update_category", ["category": "супы", "position": 1, "color": "Синий"])
        #expect(moved["position"]?.intValue == 1)
        #expect(moved["color"]?.stringValue == "blue")

        let list = try await fixture.call("list_categories")
        #expect(list["categories"]?.each("name") == ["Супы", "Завтраки"])
        #expect(list["meal_types"] == .array(["Завтрак", "Обед", "Ужин", "Перекус"]))

        _ = try await fixture.call("delete_category", ["category": "Завтраки"])
        #expect(try fixture.database.categories().map(\.name) == ["Супы"])
        #expect(await fixture.failure("create_category", ["name": "супы"]).contains("уже"))
    }
}

struct RecipeToolTests {
    private let omelette: [String: Value] = [
        "title": "Омлет с фетой",
        "servings": 2,
        "categories": ["Завтраки"],
        "meal_types": ["завтрак"],
        "ingredients": [
            "3 яйца", "40 г феты", "соль по вкусу",
            ["name": "паста мисо", "amount": 1, "unit": "ст. л.", "optional": true, "group": "Для соуса"],
        ],
        "steps": ["Взбить яйца с солью.", "Жарить под крышкой 5 минут."],
        "cook_minutes": 10,
        "source_url": "https://example.com/omelette",
    ]

    @Test func createFindsProductsCreatesTheMissingOnesAndCountsNutrition() async throws {
        let fixture = try ToolFixture()
        let recipe = try await fixture.call("create_recipe", omelette)
        #expect(recipe["title"]?.stringValue == "Омлет с фетой")
        #expect(recipe["categories"] == .array(["Завтраки"]))
        #expect(recipe["created_categories"] == .array(["Завтраки"]))
        #expect(recipe["meal_types"] == .array(["Завтрак"]))
        #expect(recipe["created_products"]?.each("name") == ["Паста мисо"])
        #expect(recipe["matched_by_search"]?.arrayValue?.contains("«феты» → «Фета»") == true)
        #expect(recipe["ingredients"]?.each("product") == ["Яйцо куриное", "Фета", "Соль", "Паста мисо"])
        #expect(recipe["ingredients"]?[3]?["group"]?.stringValue == "Для соуса")
        #expect(recipe["ingredients"]?[3]?["unit"]?.stringValue == "tbsp")
        #expect(recipe["steps"]?.arrayValue?.count == 2)
        // Eggs and feta count; the new paste has no nutrition yet and is optional.
        #expect((recipe["nutrition"]?["per_serving"]?["kcal"]?.intValue ?? 0) > 150)
        #expect(recipe["nutrition"]?["missing"] == .array(["нет КБЖУ у «Паста мисо»"]))

        let details = try #require(try fixture.database.recipe(id: Int64(recipe["id"]!.intValue!)))
        #expect(details.recipe.sourceURL == "https://example.com/omelette")
    }

    @Test func anUnclearLineChangesNothing() async throws {
        let fixture = try ToolFixture()
        let message = await fixture.failure(
            "create_recipe",
            [
                "title": "Бутерброд", "categories": ["Перекусы"],
                "ingredients": [
                    ["name": "сыр", "amount": 30, "unit": "g"], ["name": "Хлеб бородинский особый", "amount": 1],
                    "2 ложки чего-то непонятного",
                ],
            ])
        #expect(message.contains("ничего не изменилось"))
        #expect(message.contains("«сыр»: подходят"))
        #expect(message.contains("непонятного"))
        #expect(try fixture.database.recipeCards(RecipeQuery(), limit: 10).total == 0)
        #expect(try fixture.database.categories().isEmpty)
        #expect(try fixture.database.product(named: "Хлеб бородинский особый") == nil)
    }

    @Test func aLineOfTextForANewProductAsksForAnObject() async throws {
        let fixture = try ToolFixture()
        let message = await fixture.failure(
            "create_recipe", ["title": "Суп", "ingredients": ["50 г пеммикана"]])
        #expect(message.contains("объектом"))
    }

    @Test func aPhotoThatDoesNotDownloadLeavesTheRecipeWithoutIt() async throws {
        let fixture = try ToolFixture()
        var arguments = omelette
        arguments["image_url"] = "file:///etc/hosts"
        let recipe = try await fixture.call("create_recipe", arguments)
        #expect(recipe["has_photo"]?.boolValue == false)
        #expect(recipe["image_problem"]?.stringValue?.contains("set_recipe_image") == true)
        #expect(await fixture.failure("set_recipe_image", ["id": recipe["id"]!, "url": "file:///etc/hosts"]) != "")
    }

    @Test func updateChangesWhatIsGivenAndClearsWhatIsUnset() async throws {
        let fixture = try ToolFixture()
        let created = try await fixture.call("create_recipe", omelette)
        let id = try #require(created["id"])
        let updated = try await fixture.call(
            "update_recipe",
            [
                "id": id, "title": "Омлет", "servings": 3, "unset": ["source_url", "cook_minutes"],
                "nutrition_per_100g": ["kcal": 180, "protein": 12, "fat": 14, "carbs": 2],
            ])
        #expect(updated["title"]?.stringValue == "Омлет")
        #expect(updated["servings"]?.intValue == 3)
        #expect(updated["source_url"] == .null)
        #expect(updated["cook_minutes"] == .null)
        #expect(updated["ingredients"]?.arrayValue?.count == 4)
        #expect(updated["steps"]?.arrayValue?.count == 2)
        #expect(updated["categories"] == .array(["Завтраки"]))
        #expect(updated["nutrition"]?["from_source"]?.boolValue == true)
        #expect(updated["nutrition"]?["per_100g"]?["kcal"]?.intValue == 180)

        let replaced = try await fixture.call(
            "update_recipe",
            ["id": id, "ingredients": [["product_id": created["ingredients"]![0]!["product_id"]!, "amount": 4]]])
        #expect(replaced["ingredients"]?.each("product") == ["Яйцо куриное"])
        #expect(await fixture.failure("update_recipe", ["id": id, "unset": ["title"]]).contains("Можно:"))
        #expect(await fixture.failure("update_recipe", ["id": id, "servings": 0]).contains("Порций"))
    }

    @Test func getScalesTheIngredientsToTheServingsAsked() async throws {
        let fixture = try ToolFixture()
        let created = try await fixture.call("create_recipe", omelette)
        let recipe = try await fixture.call("get_recipe", ["id": created["id"]!, "servings": 4])
        #expect(recipe["ingredients_for_servings"]?.intValue == 4)
        #expect(recipe["ingredients"]?[0]?["amount"]?.intValue == 6)
        #expect(recipe["ingredients"]?[1]?["grams"]?.intValue == 80)
        #expect(recipe["nutrition"]?["per_serving"] == created["nutrition"]?["per_serving"])
    }

    @Test func searchFiltersSortsAndReadsInPages() async throws {
        let fixture = try ToolFixture()
        _ = try await fixture.call("create_recipe", omelette)
        _ = try await fixture.call(
            "create_recipe",
            [
                "title": "Сырники", "servings": 2, "categories": ["Завтраки"],
                "ingredients": [
                    ["name": "Творог 5%", "amount": 400, "unit": "g"], "1 яйцо", "2 ст. л. муки пшеничной",
                    "1 ст. л. сахара",
                ],
            ])
        _ = try await fixture.call("create_recipe", ["title": "Салат с фетой", "ingredients": ["100 г феты"]])

        let feta = try await fixture.call("search_recipes", ["query": "фета"])
        #expect(Set(feta["recipes"]?.each("title") ?? []) == ["Омлет с фетой", "Салат с фетой"])
        let withEggs = try await fixture.call("search_recipes", ["with_products": ["яйца"], "sort": "title"])
        #expect(withEggs["recipes"]?.each("title") == ["Омлет с фетой", "Сырники"])
        let withoutEggs = try await fixture.call("search_recipes", ["without_products": ["яйца"]])
        #expect(withoutEggs["recipes"]?.each("title") == ["Салат с фетой"])
        let breakfasts = try await fixture.call(
            "search_recipes", ["categories": ["завтраки"], "sort": "kcal_per_serving", "descending": true])
        #expect(breakfasts["recipes"]?.each("title") == ["Сырники", "Омлет с фетой"])

        let page = try await fixture.call("search_recipes", ["limit": 2])
        #expect(page["total"]?.intValue == 3)
        let rest = try await fixture.call("search_recipes", ["limit": 2, "cursor": page["next_cursor"]!])
        #expect(rest["recipes"]?.each("title") == ["Сырники"])
        #expect(rest["next_cursor"] == .null)
        #expect(await fixture.failure("search_recipes", ["sort": "вкус"]).contains("сортировки"))
    }

    @Test func deleteMovesTheRecipeToTheTrash() async throws {
        let fixture = try ToolFixture()
        let created = try await fixture.call("create_recipe", omelette)
        let deleted = try await fixture.call("delete_recipe", ["id": created["id"]!])
        #expect(deleted["moved_to_trash"]?.stringValue == "Омлет с фетой")
        #expect(try await fixture.call("search_recipes")["total"]?.intValue == 0)
        #expect(try await fixture.call("get_recipe", ["id": created["id"]!])["in_trash"]?.boolValue == true)
    }
}
