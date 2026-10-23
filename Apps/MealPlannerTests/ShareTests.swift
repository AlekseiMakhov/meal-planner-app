import AppKit
import Foundation
import MealCore
import MealStore
import Testing

@testable import MealPlanner

@MainActor
struct ShareTests {
    private func omelette() throws -> (AppDatabase, RecipeDetails) {
        let database = try AppDatabase.inMemory(seeded: true)
        func product(_ name: String) throws -> Product {
            guard case .found(let product) = try database.matchProduct(named: name) else { throw StoreError(name) }
            return product
        }
        var details = RecipeDetails(
            recipe: Recipe(
                id: 0, title: "Омлет с помидорами и фетой", videoURL: "https://www.youtube.com/watch?v=OSHycXV4Quo",
                servings: 2, cookMinutes: 10))
        details.ingredients = [
            RecipeIngredient(productID: try product("яйца").id, amount: 3, unit: .piece),
            RecipeIngredient(productID: try product("фета").id, amount: 40, unit: .gram, note: "кубиками"),
            RecipeIngredient(productID: try product("соль").id, unit: .toTaste),
        ]
        details.steps = [RecipeStep(text: "Взбить яйца."), RecipeStep(text: "Жарить под крышкой 5 минут.")]
        return (database, try database.newRecipe(from: details))
    }

    @Test func theTextCarriesTheRecipeForTheServingsAsked() throws {
        let (_, details) = try omelette()
        let text = RecipeShare.text(for: details, servings: 4)
        #expect(text.hasPrefix("Омлет с помидорами и фетой\n"))
        #expect(text.contains("На 4 порции · 10 мин"))
        #expect(text.contains("— Яйцо куриное — 6 шт."))
        #expect(text.contains("— Фета — 80 г (кубиками)"))
        #expect(text.contains("— Соль — по вкусу"))
        #expect(text.contains("2. Жарить под крышкой 5 минут."))
        #expect(text.contains("Видео: https://www.youtube.com/watch?v=OSHycXV4Quo"))
    }

    @Test func theCardIsAPictureAPhoneWide() throws {
        let (database, details) = try omelette()
        let file = try #require(RecipeShare.cardFile(for: details, servings: 2, images: database.images))
        #expect(file.pathExtension == "png")
        #expect(file.lastPathComponent == "Омлет с помидорами и фетой.png")
        let image = try #require(NSBitmapImageRep(data: try Data(contentsOf: file)))
        #expect(image.pixelsWide == 1170)
        #expect(image.pixelsHigh > 1200)
        #expect(RecipeShare.qrCode(for: details)?.caption == "Видео")
        #expect(RecipeShare.items(for: details, servings: 2, images: database.images).count == 2)
    }
}
