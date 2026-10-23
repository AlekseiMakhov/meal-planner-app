import Foundation
import MealCore
import Testing

@testable import MealStore

/// Recipes to filter: an omelette, a borscht and a porridge with what they are made of.
private struct Kitchen {
    let fixture: Fixture
    let egg, milk, beet, oats: Product
    let breakfast, soups: RecipeCategory
    let morning, lunch: MealType

    init() throws {
        fixture = try Fixture()
        var egg = try fixture.add("Яйцо куриное", aliases: ["яйца"], kcal: 143, protein: 12.6, fat: 9.5, carbs: 0.7)
        egg.gramsPerPiece = 50
        self.egg = try fixture.database.save(egg)
        milk = try fixture.add("Молоко", kcal: 61, protein: 3.2, fat: 3.3, carbs: 4.8)
        beet = try fixture.add("Свёкла", kcal: 43, protein: 1.6, fat: 0.2, carbs: 9.6)
        oats = try fixture.add("Овсяные хлопья", aliases: ["геркулес"])
        breakfast = try fixture.database.newCategory(named: "Завтраки")
        soups = try fixture.database.newCategory(named: "Супы")
        let meals = try fixture.database.mealTypes()
        morning = meals[0]
        lunch = meals[1]

        try fixture.addRecipe(
            "Омлет", [(self.egg, 3, .piece), (milk, 50, .gram)], servings: 1, categories: [breakfast.id],
            mealTypes: [morning.id], steps: ["Взбить и пожарить"], minutes: 10, favorite: true, photo: "omelette.jpg")
        try fixture.addRecipe(
            "Борщ", [(beet, 300, .gram)], servings: 4, categories: [soups.id], mealTypes: [lunch.id],
            notes: "Подавать со сметаной", minutes: 90, video: "https://youtu.be/OSHycXV4Quo")
        try fixture.addRecipe(
            "Каша овсяная", [(oats, 50, .gram), (milk, 200, .gram)], servings: 1, categories: [breakfast.id, soups.id],
            mealTypes: [morning.id], minutes: 15)
    }
}

struct RecipeQueryTests {
    @Test func searchFindsTitlesProductsStepsAndNotesInAnyForm() throws {
        let kitchen = try Kitchen()
        let fixture = kitchen.fixture
        #expect(try fixture.titles(RecipeQuery(text: "омлета")) == ["Омлет"])
        #expect(try fixture.titles(RecipeQuery(text: "свеклы")) == ["Борщ"], "by product, without «ё»")
        #expect(try fixture.titles(RecipeQuery(text: "геркулес")) == ["Каша овсяная"], "by a product's alias")
        #expect(try fixture.titles(RecipeQuery(text: "взбить")) == ["Омлет"], "by a step")
        #expect(try fixture.titles(RecipeQuery(text: "сметаной")) == ["Борщ"], "by the notes")
        #expect(try fixture.titles(RecipeQuery(text: "молоко")) == ["Каша овсяная", "Омлет"])
    }

    @Test func filtersByCategoryMealAndProducts() throws {
        let kitchen = try Kitchen()
        let fixture = kitchen.fixture
        #expect(try fixture.titles(RecipeQuery(categoryIDs: [kitchen.soups.id])) == ["Борщ", "Каша овсяная"])
        #expect(try fixture.titles(RecipeQuery(mealTypeIDs: [kitchen.morning.id])) == ["Каша овсяная", "Омлет"])
        #expect(try fixture.titles(RecipeQuery(withProducts: [kitchen.milk.id, kitchen.egg.id])) == ["Омлет"])
        #expect(try fixture.titles(RecipeQuery(withoutProducts: [kitchen.milk.id])) == ["Борщ"])
    }

    @Test func filtersByNutritionPerServing() throws {
        let kitchen = try Kitchen()
        let fixture = kitchen.fixture
        // Омлет: 150 г яиц и 50 г молока на порцию — 245 ккал; борщ — 32 ккал. У каши посчитано только молоко
        // (122 ккал): у овсянки нет КБЖУ, и каша помечена как посчитанная не полностью.
        #expect(try fixture.titles(RecipeQuery(kcalPerServing: ValueRange(max: 200))) == ["Борщ", "Каша овсяная"])
        #expect(try fixture.titles(RecipeQuery(kcalPerServing: ValueRange(min: 200))) == ["Омлет"])
        #expect(try fixture.titles(RecipeQuery(protein: ValueRange(min: 10))) == ["Омлет"])
        #expect(try fixture.titles(RecipeQuery(nutritionIncomplete: true)) == ["Каша овсяная"])
        #expect(try fixture.titles(RecipeQuery(nutritionIncomplete: false)) == ["Борщ", "Омлет"])
    }

    @Test func filtersByTimeFavoritePhotoAndVideo() throws {
        let kitchen = try Kitchen()
        let fixture = kitchen.fixture
        #expect(try fixture.titles(RecipeQuery(maxMinutes: 15)) == ["Каша овсяная", "Омлет"])
        #expect(try fixture.titles(RecipeQuery(isFavorite: true)) == ["Омлет"])
        #expect(try fixture.titles(RecipeQuery(hasPhoto: true)) == ["Омлет"])
        #expect(try fixture.titles(RecipeQuery(hasVideo: true)) == ["Борщ"])
        #expect(try fixture.titles(RecipeQuery(hasVideo: false)) == ["Каша овсяная", "Омлет"])
    }

    @Test func sortsWithEmptyValuesLast() throws {
        let kitchen = try Kitchen()
        let fixture = kitchen.fixture
        #expect(
            try fixture.titles(RecipeQuery(sort: [SortTerm(.protein, .descending)])) == [
                "Омлет", "Каша овсяная", "Борщ",
            ])
        #expect(
            try fixture.titles(RecipeQuery(sort: [SortTerm(.kcalPerServing)])) == ["Борщ", "Каша овсяная", "Омлет"])
        try kitchen.fixture.addRecipe("Вода")
        #expect(
            try fixture.titles(RecipeQuery(sort: [SortTerm(.kcalPerServing, .descending)])).last == "Вода",
            "a recipe without nutrition goes last either way")
        #expect(
            try fixture.titles(RecipeQuery(sort: [SortTerm(.totalTime)])) == ["Омлет", "Каша овсяная", "Борщ", "Вода"])
    }

    @Test func cardsCarryTheirCategories() throws {
        let kitchen = try Kitchen()
        let porridge = try #require(
            try kitchen.fixture.database.recipeCards(RecipeQuery(text: "каша"), limit: 1).rows.first)
        #expect(porridge.categoryIDs == [kitchen.breakfast.id, kitchen.soups.id])
    }

    @Test func galleryGroupsByCategoryWithUncategorizedLast() throws {
        let kitchen = try Kitchen()
        let database = kitchen.fixture.database
        try kitchen.fixture.addRecipe("Чай")
        let page = try database.recipeGallery(RecipeGalleryQuery(), limit: 100)
        #expect(page.rows.map(\.card.title) == ["Каша овсяная", "Омлет", "Борщ", "Каша овсяная", "Чай"])
        #expect(
            page.rows.map(\.categoryID) == [
                kitchen.breakfast.id, kitchen.breakfast.id, kitchen.soups.id, kitchen.soups.id, nil,
            ])
        #expect(Set(page.rows.map(\.id)).count == 5, "a recipe in two groups has two ids")
    }

    @Test func collapsedGroupsKeepTheirCountsButNotTheirCards() async throws {
        let kitchen = try Kitchen()
        let database = kitchen.fixture.database
        try kitchen.fixture.addRecipe("Чай")
        let query = RecipeGalleryQuery(collapsed: [kitchen.breakfast.id, nil])
        #expect(try database.recipeGallery(query, limit: 100).rows.map(\.card.title) == ["Борщ", "Каша овсяная"])
        var groups = database.observeRecipeGroups(RecipeQuery()).makeAsyncIterator()
        let counts = try #require(try await groups.next())
        #expect(
            counts == [
                RecipeGroup(categoryID: kitchen.breakfast.id, count: 2),
                RecipeGroup(categoryID: kitchen.soups.id, count: 2),
                RecipeGroup(categoryID: nil, count: 1),
            ])
    }

    @Test func galleryFilteredByCategoryShowsOnlyThatGroup() throws {
        let kitchen = try Kitchen()
        let page = try kitchen.fixture.database.recipeGallery(
            RecipeGalleryQuery(recipes: RecipeQuery(categoryIDs: [kitchen.soups.id])), limit: 100)
        #expect(page.rows.map(\.categoryID) == [kitchen.soups.id, kitchen.soups.id])
        #expect(page.total == 2)
    }

    @Test func productsUsedInRecipesFilterAndSort() throws {
        let kitchen = try Kitchen()
        let fixture = kitchen.fixture
        try fixture.add("Соль")
        #expect(try fixture.names(ProductQuery(isUsedInRecipes: false)) == ["Соль"])
        #expect(try fixture.names(ProductQuery(isUsedInRecipes: true)).count == 4)
        #expect(try fixture.names(ProductQuery(sort: [SortTerm(.recipeCount, .descending)])).first == "Молоко")
    }
}
