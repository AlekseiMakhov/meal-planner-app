import Foundation
import MealCore
import MealStore
import PDFKit
import Testing

@testable import MealPlanner

@MainActor
struct MenuPDFTests {
    @Test func theWeekThenEachRecipeOnce() throws {
        let database = try AppDatabase.inMemory(seeded: true)
        guard case .found(let eggs) = try database.matchProduct(named: "яйца") else { throw StoreError("яйца") }
        var omelette = RecipeDetails(recipe: Recipe(id: 0, title: "Омлет", servings: 2))
        omelette.ingredients = [RecipeIngredient(productID: eggs.id, amount: 3, unit: .piece)]
        omelette.steps = [RecipeStep(text: "Пожарить.")]
        let saved = try database.newRecipe(from: omelette)
        let meals = try database.mealTypes()
        let monday = Day(year: 2026, month: 10, day: 19)
        try database.planMeal(on: monday, meal: meals[0].id, recipe: saved.recipe.id)
        try database.planMeal(on: monday.adding(days: 2), meal: meals[0].id, recipe: saved.recipe.id, servings: 4)
        try database.planMeal(on: monday.adding(days: 2), meal: meals[2].id, text: "Ужин в гостях")
        let plan = try database.weekPlan(starting: monday)

        let file = FileManager.default.temporaryDirectory.appending(
            path: "menu \(UUID().uuidString)/\(MenuPDF.fileName(plan))")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try MenuPDF.write(plan, images: database.images, to: file)
        #expect(file.lastPathComponent == "Меню 19–25 октября.pdf")
        let document = try #require(PDFDocument(url: file))
        #expect(document.pageCount == 2)
        let overview = document.page(at: 0)?.string ?? ""
        #expect(overview.contains("Омлет (2 порции)"))
        #expect(overview.contains("Ужин в гостях"))
        #expect(document.page(at: 1)?.string?.contains("Пожарить.") == true)
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).width == RecipeShare.width)
    }
}
