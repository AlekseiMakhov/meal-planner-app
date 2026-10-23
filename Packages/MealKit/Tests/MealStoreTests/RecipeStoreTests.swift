import Foundation
import GRDB
import MealCore
import Testing

@testable import MealStore

extension Fixture {
    /// A recipe with the given lines: (product, amount, unit).
    @discardableResult
    func addRecipe(
        _ title: String, _ lines: [(Product, Double?, MeasureUnit?)] = [], servings: Int = 2,
        categories: [RecipeCategory.ID] = [], mealTypes: Set<MealType.ID> = [], steps: [String] = [],
        notes: String = "", minutes: Int? = nil, favorite: Bool = false, photo: String? = nil, video: String? = nil
    ) throws -> RecipeDetails {
        var details = try database.newRecipe()
        details.recipe.title = title
        details.recipe.servings = servings
        details.recipe.notes = notes
        details.recipe.cookMinutes = minutes
        details.recipe.isFavorite = favorite
        details.recipe.photo = photo
        details.recipe.videoURL = video
        details.ingredients = lines.map { RecipeIngredient(productID: $0.0.id, amount: $0.1, unit: $0.2) }
        details.steps = steps.map { RecipeStep(text: $0) }
        details.categoryIDs = categories
        details.mealTypeIDs = mealTypes
        return try database.save(details)
    }

    func titles(_ query: RecipeQuery, limit: Int = 100) throws -> [String] {
        try database.recipeCards(query, limit: limit).rows.map(\.title)
    }
}

struct RecipeStoreTests {
    @Test func newRecipeIsEmptyForTwo() throws {
        let fixture = try Fixture()
        let category = try fixture.database.newCategory(named: "Завтраки")
        let details = try fixture.database.newRecipe(in: [category.id])
        #expect(details.recipe.title == "Новый рецепт")
        #expect(details.recipe.servings == 2)
        #expect(details.categoryIDs == [category.id])
        #expect(details.ingredients.isEmpty)
    }

    /// The omelette from the Notion base, typed line by line against the starting product base.
    @Test func omeletteFromTypedLines() throws {
        let database = try AppDatabase.inMemory(seeded: true)
        let lines = [
            "Яйца — 3 шт.", "Молоко — 3 ст. л.", "Помидоры черри — 10 шт.", "Фета — 40 г", "Петрушка",
            "Паприка", "Соль",
        ]
        var details = try database.newRecipe()
        details.recipe.title = "Омлет с помидорами и фетой"
        for line in lines {
            let parsed = try #require(IngredientParser.parse(line).first)
            let product = try #require(try database.product(named: parsed.name), "\(parsed.name)")
            details.ingredients.append(
                RecipeIngredient(productID: product.id, amount: parsed.amount, unit: parsed.unit, note: parsed.note))
        }
        details.steps = ["Взбить яйца с молоком и щепоткой соли", "Обжарить помидоры", "Залить яйцом", " "].map {
            RecipeStep(text: $0)
        }
        let saved = try database.save(details)
        #expect(saved.steps.count == 3, "the empty step is dropped")
        #expect(saved.ingredients.count == 7)
        #expect(saved.products.count == 7)

        let card = try #require(try database.recipeCards(RecipeQuery(), limit: 10).rows.first)
        let nutrition = saved.nutrition
        #expect(card.perServing?.kcal == nutrition.perServing?.kcal)
        #expect(try #require(card.perServing?.kcal) > 150)
        #expect(card.isNutritionComplete)
        #expect(card.kcalPer100 == nutrition.per100g?.kcal)
    }

    @Test func savingRefusesWhatCannotBeSaved() throws {
        let fixture = try Fixture()
        var details = try fixture.database.newRecipe()
        details.recipe.title = "  "
        #expect(throws: StoreError("Нужно название.")) { try fixture.database.save(details) }
        details.recipe.title = "Суп"
        details.ingredients = [RecipeIngredient(productID: 999, amount: 1)]
        #expect(throws: StoreError.self) { try fixture.database.save(details) }
    }

    @Test func savingKeepsCategoriesAndMeals() throws {
        let fixture = try Fixture()
        let soups = try fixture.database.newCategory(named: "Супы")
        let quick = try fixture.database.newCategory(named: "Быстрые")
        let lunch = try #require(try fixture.database.mealTypes().first { $0.name == "Обед" })
        let saved = try fixture.addRecipe("Борщ", categories: [quick.id, soups.id], mealTypes: [lunch.id])
        #expect(saved.categoryIDs == [soups.id, quick.id], "in the categories' own order")
        #expect(saved.mealTypeIDs == [lunch.id])
    }

    @Test func aProductsChangeReachesItsRecipes() throws {
        let fixture = try Fixture()
        var egg = try fixture.add("Яйцо", kcal: 143, protein: 12.6, fat: 9.5, carbs: 0.7)
        egg.gramsPerPiece = 50
        egg = try fixture.database.save(egg)
        try fixture.addRecipe("Яичница", [(egg, 2, .piece)], servings: 1)
        #expect(try fixture.database.recipeCards(RecipeQuery(), limit: 1).rows.first?.perServing?.kcal == 143)

        egg.kcal = 157
        egg.name = "Яйцо С1"
        try fixture.database.save(egg)
        let card = try #require(try fixture.database.recipeCards(RecipeQuery(), limit: 1).rows.first)
        #expect(card.perServing?.kcal == 157)
        #expect(try fixture.titles(RecipeQuery(text: "с1")) == ["Яичница"], "the search follows the product's name")
    }

    @Test func aProductInARecipeCannotBeDeleted() throws {
        let fixture = try Fixture()
        let feta = try fixture.add("Фета")
        let recipe = try fixture.addRecipe("Салат", [(feta, 40, .gram)])
        #expect(throws: StoreError("«Фета» есть в 1 рецепте. Уберите его оттуда или объедините с другим продуктом.")) {
            try fixture.database.deleteProduct(id: feta.id)
        }
        #expect(try fixture.database.recipeCount(of: feta.id) == 1)
        var details = recipe
        details.ingredients = []
        try fixture.database.save(details)
        try fixture.database.deleteProduct(id: feta.id)
        #expect(try fixture.database.product(id: feta.id) == nil)
    }

    @Test func mergingMovesRecipesToTheKeptProduct() throws {
        let fixture = try Fixture()
        let kept = try fixture.add("Яйцо куриное", kcal: 143, protein: 12.6, fat: 9.5, carbs: 0.7)
        let duplicate = try fixture.add("Яйца")
        let recipe = try fixture.addRecipe("Омлет", [(duplicate, 3, .piece)])
        try fixture.database.mergeProduct(duplicate.id, into: kept.id)
        let details = try #require(try fixture.database.recipe(id: recipe.recipe.id))
        #expect(details.ingredients.map(\.productID) == [kept.id])
        #expect(try fixture.database.recipeCount(of: kept.id) == 1)
    }

    @Test func duplicateHasItsOwnPhotoAndContent() throws {
        let fixture = try Fixture()
        let feta = try fixture.add("Фета")
        let photo = try fixture.database.images.save(ImageStoreTests.png(width: 40, height: 30))
        let original = try fixture.addRecipe(
            "Салат", [(feta, 40, .gram)], steps: ["Нарезать"], favorite: true, photo: photo)
        let copy = try fixture.database.duplicateRecipe(id: original.recipe.id)
        #expect(copy.recipe.title == "Салат (копия)")
        #expect(copy.recipe.id != original.recipe.id)
        #expect(!copy.recipe.isFavorite)
        #expect(copy.ingredients.map(\.productID) == [feta.id])
        #expect(copy.steps.map(\.text) == ["Нарезать"])
        let copyPhoto = try #require(copy.recipe.photo)
        #expect(copyPhoto != photo)
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.database.images.url(for: copyPhoto).path(percentEncoded: false)))
    }

    @Test func replacedPhotoIsRemoved() throws {
        let fixture = try Fixture()
        let first = try fixture.database.images.save(ImageStoreTests.png(width: 10, height: 10))
        var recipe = try fixture.addRecipe("Суп", photo: first)
        recipe.recipe.photo = try fixture.database.images.save(ImageStoreTests.png(width: 10, height: 10))
        try fixture.database.save(recipe)
        #expect(
            !FileManager.default.fileExists(atPath: fixture.database.images.url(for: first).path(percentEncoded: false))
        )
    }

    @Test func trashHidesAndRestores() throws {
        let fixture = try Fixture()
        let category = try fixture.database.newCategory(named: "Супы")
        let photo = try fixture.database.images.save(ImageStoreTests.png(width: 10, height: 10))
        let soup = try fixture.addRecipe("Суп", categories: [category.id], photo: photo)
        try fixture.addRecipe("Каша")

        try fixture.database.moveRecipeToTrash(id: soup.recipe.id)
        #expect(try fixture.titles(RecipeQuery()) == ["Каша"])
        #expect(try fixture.database.recipeGallery(RecipeGalleryQuery(), limit: 10).rows.map(\.card.title) == ["Каша"])
        try fixture.database.restoreRecipe(id: soup.recipe.id)
        #expect(try fixture.titles(RecipeQuery()) == ["Каша", "Суп"])

        try fixture.database.moveRecipeToTrash(id: soup.recipe.id)
        #expect(try fixture.database.emptyTrash(olderThan: 30) == 0, "a fresh deletion waits 30 days")
        #expect(try fixture.database.emptyTrash(olderThan: 0) == 1)
        #expect(try fixture.database.recipe(id: soup.recipe.id) == nil)
        #expect(
            !FileManager.default.fileExists(atPath: fixture.database.images.url(for: photo).path(percentEncoded: false))
        )
    }

    @Test func favoriteIsSetWithoutSavingTheRecipe() throws {
        let fixture = try Fixture()
        let recipe = try fixture.addRecipe("Суп")
        try fixture.database.setFavorite(true, recipeID: recipe.recipe.id)
        #expect(try fixture.titles(RecipeQuery(isFavorite: true)) == ["Суп"])
    }
}

struct CategoryStoreTests {
    @Test func newCategoriesGoLastInTheirOwnColour() throws {
        let fixture = try Fixture()
        let first = try fixture.database.newCategory(named: "Завтраки")
        let second = try fixture.database.newCategory(named: " Супы ")
        #expect(second.name == "Супы")
        #expect(second.position == first.position + 1)
        #expect(first.color != second.color)
        #expect(throws: StoreError("Категория «Супы» уже есть.")) { try fixture.database.newCategory(named: "СУПЫ") }
        #expect(throws: StoreError("Нужно название.")) { try fixture.database.newCategory(named: " ") }
    }

    @Test func renamingRecolouringAndReordering() throws {
        let fixture = try Fixture()
        var breakfast = try fixture.database.newCategory(named: "Завтраки")
        let soups = try fixture.database.newCategory(named: "Супы")
        breakfast.name = "Утро"
        breakfast.color = .orange
        try fixture.database.save(breakfast)
        try fixture.database.reorderCategories([soups.id, breakfast.id])
        let categories = try fixture.database.categories()
        #expect(categories.map(\.name) == ["Супы", "Утро"])
        #expect(categories.last?.color == .orange)
        var taken = breakfast
        taken.name = "супы"
        #expect(throws: StoreError.self) { try fixture.database.save(taken) }
    }

    @Test func deletingACategoryKeepsItsRecipes() throws {
        let fixture = try Fixture()
        let soups = try fixture.database.newCategory(named: "Супы")
        try fixture.addRecipe("Борщ", categories: [soups.id])
        try fixture.database.deleteCategory(id: soups.id)
        #expect(try fixture.titles(RecipeQuery()) == ["Борщ"])
        #expect(try fixture.database.recipeCards(RecipeQuery(), limit: 1).rows.first?.categoryIDs == [])
    }

    @Test func countsLeaveOutTheTrash() async throws {
        let fixture = try Fixture()
        let soups = try fixture.database.newCategory(named: "Супы")
        try fixture.addRecipe("Борщ", categories: [soups.id])
        let trashed = try fixture.addRecipe("Щи", categories: [soups.id])
        try fixture.database.moveRecipeToTrash(id: trashed.recipe.id)
        var iterator = fixture.database.observeCategories().makeAsyncIterator()
        let summaries = try #require(try await iterator.next())
        #expect(summaries.map(\.count) == [1])
    }

    @Test func mealTypesStartWithTheFourMeals() throws {
        let fixture = try Fixture()
        #expect(try fixture.database.mealTypes().map(\.name) == ["Завтрак", "Обед", "Ужин", "Перекус"])
    }
}
