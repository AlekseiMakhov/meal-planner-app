import Foundation
import GRDB
import MealCore
import Testing

@testable import MealStore

struct LibraryTests {
    private func folder(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "\(name) \(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// A household on the starting base: a recipe worth keeping with a photo, an empty draft, a recipe in the
    /// trash, a pantry, a shopping list linked with «Напоминания», and a cooked dish.
    private func household() throws -> AppDatabase {
        let database = try AppDatabase.inMemory(seeded: true)
        guard case .found(let eggs) = try database.matchProduct(named: "яйца") else {
            throw StoreError("нет яиц в начальной базе")
        }
        let breakfasts = try database.newCategory(named: "Завтраки")
        var omelette = RecipeDetails(recipe: Recipe(id: 0, title: "Омлет", servings: 2))
        omelette.ingredients = [RecipeIngredient(productID: eggs.id, amount: 3, unit: .piece)]
        omelette.steps = [RecipeStep(text: "Взбить и пожарить.")]
        omelette.categoryIDs = [breakfasts.id]
        omelette.recipe.photo = try database.images.save(ImageStoreTests.png(width: 10, height: 10))
        omelette = try database.newRecipe(from: omelette)
        _ = try database.newRecipe()
        var soup = RecipeDetails(recipe: Recipe(id: 0, title: "Старый суп", servings: 2))
        soup.steps = [RecipeStep(text: "Сварить.")]
        try database.moveRecipeToTrash(id: try database.newRecipe(from: soup).recipe.id)
        try database.setPantry(eggs.id, quantity: 10)
        let bread = try #require(try database.addToShopping([ShoppingAddition(text: "Хлеб")]).first)
        try database.writer.write { db in
            try db.execute(
                sql:
                    "INSERT INTO reminder_link (shoppingItemId, reminderId, title, isChecked) VALUES (?, 'r1', 'Хлеб', 0)",
                arguments: [bread])
            try db.execute(sql: "INSERT INTO reminder_known (reminderId) VALUES ('r1')")
        }
        let breakfast = try #require(try database.mealTypes().first)
        let dish = try database.planMeal(on: .today(), meal: breakfast.id, recipe: omelette.recipe.id)
        try database.markCooked(dish.id, using: [:])
        return database
    }

    @Test func theLibraryKeepsTheRecipesAndLeavesTheHouseholdBehind() throws {
        let household = try household()
        let library = folder("library")
        defer { try? FileManager.default.removeItem(at: library) }
        try household.exportLibrary(to: library)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: library.path(percentEncoded: false)).sorted()
                == ["Images", "meals.sqlite"])

        let newMac = folder("new mac")
        defer { try? FileManager.default.removeItem(at: newMac) }
        let database = try AppDatabase.open(in: newMac, library: library)
        let cards = try database.recipeCards(RecipeQuery(), limit: 10).rows
        #expect(cards.map(\.title) == ["Омлет"], "the draft and the trash stay behind")
        #expect(try database.categories().map(\.name) == ["Завтраки"])
        #expect(cards.first?.categoryIDs.count == 1)
        #expect(cards.first?.missingCount == 1, "counted again for an empty pantry")
        #expect(cards.first?.lastCookedAt == nil)
        #expect(
            try database.products(ProductQuery(), limit: 1).total == household.products(ProductQuery(), limit: 1).total)
        #expect(try database.pantry(PantryQuery(), limit: 10).total == 0)
        #expect(try database.shopping(ShoppingQuery(), limit: 10).total == 0)
        #expect(try database.weekPlan(starting: Day.today().weekStart).entries.isEmpty)
        let links = try database.writer.read { db in
            try Int.fetchOne(
                db, sql: "SELECT (SELECT COUNT(*) FROM reminder_link) + (SELECT COUNT(*) FROM reminder_known)")
        }
        #expect(links == 0)
        let omelette = try #require(cards.first)
        let photo = try #require(try database.recipe(id: omelette.id)?.recipe.photo)
        #expect(FileManager.default.fileExists(atPath: database.images.url(for: photo).path(percentEncoded: false)))

        #expect(try household.pantry(PantryQuery(), limit: 10).total == 1, "the household itself is left as it was")
    }

    @Test func aFolderWithADatabaseOfItsOwnKeepsIt() throws {
        let library = folder("library")
        defer { try? FileManager.default.removeItem(at: library) }
        try household().exportLibrary(to: library)
        let myMac = folder("my mac")
        defer { try? FileManager.default.removeItem(at: myMac) }
        _ = try AppDatabase.open(in: myMac).newCategory(named: "Мои")

        let database = try AppDatabase.open(in: myMac, library: library)
        #expect(try database.categories().map(\.name) == ["Мои"])
        #expect(try database.recipeCards(RecipeQuery(), limit: 10).total == 0)
    }

    @Test func withoutALibraryANewFolderStartsWithTheProductBase() throws {
        let newMac = folder("new mac")
        defer { try? FileManager.default.removeItem(at: newMac) }
        let database = try AppDatabase.open(in: newMac, library: folder("no library"))
        #expect(try database.recipeCards(RecipeQuery(), limit: 10).total == 0)
        #expect(try database.products(ProductQuery(), limit: 1).total > 300)
    }
}
