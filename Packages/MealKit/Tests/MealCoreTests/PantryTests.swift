import Foundation
import MealCore
import Testing

struct PantryTests {
    private let egg = Product(id: 1, name: "Яйцо куриное", baseUnit: .piece, gramsPerPiece: 50)
    private let milk = Product(id: 2, name: "Молоко 3,2%", baseUnit: .milliliter, density: 1.031)
    private let feta = Product(id: 3, name: "Фета")
    private let dill = Product(id: 4, name: "Укроп")
    private let salt = Product(id: 5, name: "Соль", isStaple: true)
    private let garlic = Product(id: 6, name: "Чеснок", baseUnit: .piece, namedUnits: [.clove: 5])

    private func home(_ product: Product, _ quantity: Double?, low: Bool = false) -> PantryItem {
        PantryItem(productID: product.id, quantity: quantity, isLow: low)
    }

    @Test func statusFollowsTheAmountAndTheMark() {
        #expect(home(egg, 6).status == .inStock)
        #expect(home(egg, 2, low: true).status == .low)
        #expect(home(egg, 0).status == .out)
        #expect(home(egg, 0, low: true).status == .out)
        #expect(home(salt, nil).status == .inStock)
        #expect(home(egg, 0.3 + 0.7 - 1).status == .out)
    }

    @Test func aLineIsCoveredShortOrMissing() {
        let eggs = RecipeIngredient(productID: 1, amount: 3, unit: .piece)
        #expect(eggs.availability(of: egg, at: home(egg, 10)) == .enough)
        #expect(eggs.availability(of: egg, at: home(egg, 3)) == .enough)
        #expect(eggs.availability(of: egg, at: home(egg, 1)) == .low(missing: 2))
        #expect(eggs.availability(of: egg, at: home(egg, 0)) == .missing(needed: 3))
        #expect(eggs.availability(of: egg, at: nil) == .missing(needed: 3))
        // Some, uncounted: nobody weighed it, so it is taken to be enough.
        #expect(eggs.availability(of: egg, at: home(egg, nil)) == .enough)
    }

    @Test func amountsConvertToWhatThePantryCounts() {
        let spoons = RecipeIngredient(productID: 2, amount: 3, unit: .tablespoon)
        #expect(spoons.availability(of: milk, at: home(milk, 1000)) == .enough)
        #expect(spoons.availability(of: milk, at: home(milk, 30)) == .low(missing: 15))
        let cloves = RecipeIngredient(productID: 6, amount: 2, amountMax: 3, unit: .clove)
        // The top of the range: three cloves, 15 g, of a head counted in pieces without a weight.
        #expect(cloves.availability(of: garlic, at: home(garlic, 1)) == .unknown)
        #expect(cloves.availability(of: garlic, at: nil) == .missing(needed: nil))
        let bunch = RecipeIngredient(productID: 4, amount: 1, unit: .bunch)
        #expect(bunch.availability(of: dill, at: home(dill, 100)) == .unknown)
    }

    @Test func staplesAndLinesToTasteOnlyNeedToBeThere() {
        let salted = RecipeIngredient(productID: 5, unit: .toTaste)
        #expect(salted.availability(of: salt, at: home(salt, nil)) == .enough)
        #expect(salted.availability(of: salt, at: home(salt, 0)) == .missing(needed: nil))
        let spoon = RecipeIngredient(productID: 5, amount: 1, unit: .teaspoon)
        #expect(spoon.availability(of: salt, at: home(salt, nil)) == .enough)
        let parsley = RecipeIngredient(productID: 4)
        #expect(parsley.availability(of: dill, at: home(dill, 20)) == .enough)
        #expect(parsley.availability(of: dill, at: nil) == .missing(needed: nil))
    }

    @Test func shortagesBuyWhatIsMissingInThePantrysUnit() {
        let reason = ShoppingReason(recipeID: 7, title: "Омлет")
        let eggs = RecipeIngredient(productID: 1, amount: 3, unit: .piece)
        #expect(eggs.shortage(of: egg, at: home(egg, 10), reason: reason) == nil)
        #expect(
            eggs.shortage(of: egg, at: home(egg, 1), reason: reason)
                == ShoppingAddition(product: 1, amount: 2, unit: .piece, reason: reason))
        let bunch = RecipeIngredient(productID: 4, amount: 1, unit: .bunch)
        // No weight for the bunch: the line's own amount goes on the list.
        #expect(
            bunch.shortage(of: dill, at: nil, reason: reason)
                == ShoppingAddition(product: 4, amount: 1, unit: .bunch, reason: reason))
        let salted = RecipeIngredient(productID: 5, amount: 1, unit: .teaspoon)
        #expect(
            salted.shortage(of: salt, at: nil, reason: reason)
                == ShoppingAddition(product: 5, amount: nil, unit: nil, reason: reason))
    }

    @Test func aRecipeCountsItsMissingLinesForTheServingsAsked() {
        let details = RecipeDetails(
            recipe: Recipe(id: 7, title: "Омлет", servings: 2),
            ingredients: [
                RecipeIngredient(productID: 1, amount: 3, unit: .piece),
                RecipeIngredient(productID: 3, amount: 40, unit: .gram),
                RecipeIngredient(productID: 4, amount: 1, unit: .bunch),
                RecipeIngredient(productID: 5, unit: .toTaste),
                RecipeIngredient(productID: 2, amount: 50, unit: .milliliter, isOptional: true),
            ],
            products: Dictionary(uniqueKeysWithValues: [egg, milk, feta, dill, salt].map { ($0.id, $0) }))
        let pantry: [Product.ID: PantryItem] = [
            1: home(egg, 4), 3: home(feta, 100), 4: home(dill, 50), 5: home(salt, nil),
        ]
        let forTwo = details.availability(pantry: pantry)
        #expect(forTwo.missingCount == 0)
        #expect(forTwo.unknownCount == 1)
        let forFour = details.availability(servings: 4, pantry: pantry)
        // Six eggs for four, four at home; the missing milk is optional.
        #expect(forFour.missingCount == 1)
        #expect(forFour.lines[details.ingredients[0].id] == .low(missing: 2))
        #expect(details.availability(pantry: [:]).missingCount == 4)
        let shortages = details.shortages(servings: 4, pantry: pantry)
        #expect(shortages.map(\.productID) == [1])
        #expect(shortages.first?.reason?.title == "Омлет")
    }

    @Test func aShoppingLineWeighsInThePantrysUnit() {
        let bought = ShoppingEntry(item: ShoppingItem(id: 1, productID: 2, amount: 1, unit: .liter), product: milk)
        #expect(bought.amountInBaseUnit == 1000)
        let eggs = ShoppingEntry(item: ShoppingItem(id: 2, productID: 1, amount: 10), product: egg)
        #expect(eggs.amountInBaseUnit == 10)
        let text = ShoppingEntry(item: ShoppingItem(id: 3, text: "Батарейки", amount: 4))
        #expect(text.amountInBaseUnit == nil)
        #expect(text.name == "Батарейки")
    }
}
