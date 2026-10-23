import Foundation
import GRDB
import MealCore
import Testing

@testable import MealStore

struct PantryStoreTests {
    private func products(_ fixture: Fixture) throws -> (eggs: Product, milk: Product, salt: Product, dill: Product) {
        var eggs = try fixture.add("Яйцо куриное", aliases: ["яйца"], aisle: "Молочное")
        eggs.baseUnit = .piece
        eggs.gramsPerPiece = 50
        eggs = try fixture.database.save(eggs)
        var milk = try fixture.add("Молоко", aisle: "Молочное")
        milk.baseUnit = .milliliter
        milk.density = 1.03
        milk = try fixture.database.save(milk)
        let salt = try fixture.add("Соль", aisle: "Специи", staple: true)
        let dill = try fixture.add("Укроп", aisle: "Овощи")
        return (eggs, milk, salt, dill)
    }

    private func names(_ database: AppDatabase, _ query: PantryQuery) throws -> [String] {
        try database.pantry(query, limit: 100).rows.map(\.product.name)
    }

    @Test func thePantryListsWhatIsThereByAisleAndStatus() throws {
        let fixture = try Fixture()
        let (eggs, milk, salt, dill) = try products(fixture)
        try fixture.database.setPantry(eggs.id, quantity: 6)
        try fixture.database.setPantry(milk.id, quantity: 200, isLow: true)
        try fixture.database.setPantry(salt.id, quantity: nil)
        try fixture.database.setPantry(dill.id, quantity: 0)

        #expect(try names(fixture.database, PantryQuery()) == ["Укроп", "Молоко", "Яйцо куриное", "Соль"])
        #expect(
            try names(fixture.database, PantryQuery(sort: [SortTerm(.name)])) == [
                "Молоко", "Соль", "Укроп", "Яйцо куриное",
            ])
        #expect(try names(fixture.database, PantryQuery(statuses: [.low])) == ["Молоко"])
        #expect(try names(fixture.database, PantryQuery(statuses: [.inStock])) == ["Яйцо куриное", "Соль"])
        #expect(try names(fixture.database, PantryQuery(statuses: [.out, .low])) == ["Укроп", "Молоко"])
        #expect(try names(fixture.database, PantryQuery(text: "яйца")) == ["Яйцо куриное"])
        #expect(try names(fixture.database, PantryQuery(aisleIDs: [fixture.aisles["Специи"]!])) == ["Соль"])
        let byAmount = PantryQuery(sort: [SortTerm(.quantity, .descending)])
        #expect(try names(fixture.database, byAmount) == ["Молоко", "Яйцо куриное", "Укроп", "Соль"])

        #expect(try fixture.names(ProductQuery(isAtHome: true)) == ["Молоко", "Соль", "Яйцо куриное"])
        #expect(try fixture.names(ProductQuery(isAtHome: false)) == ["Укроп"])
    }

    @Test func addingToThePantrySumsAndBuyingEndsRunningLow() throws {
        let fixture = try Fixture()
        let (eggs, _, salt, dill) = try products(fixture)
        try fixture.database.setPantry(eggs.id, quantity: 2, isLow: true)
        try fixture.database.addToPantry([eggs.id: 10, salt.id: nil, dill.id: nil])
        let items = try fixture.database.pantryItems(for: [eggs.id, salt.id, dill.id])
        #expect(items[eggs.id]?.quantity == 12)
        #expect(items[eggs.id]?.isLow == false)
        #expect(items[salt.id]?.quantity == nil)
        #expect(items[salt.id]?.isInStock == true)

        try fixture.database.takeFromPantry([eggs.id: 20])
        #expect(try fixture.database.pantryItem(productID: eggs.id)?.quantity == 0)
        #expect(throws: StoreError.self) { try fixture.database.setPantry(eggs.id, quantity: -1) }
        try fixture.database.removeFromPantry([eggs.id])
        #expect(try fixture.database.pantryItem(productID: eggs.id) == nil)
    }

    @Test func recipesCountWhatIsMissingAsThePantryChanges() throws {
        let fixture = try Fixture()
        let (eggs, milk, salt, _) = try products(fixture)
        let omelette = try fixture.addRecipe(
            "Омлет", [(eggs, 3, .piece), (milk, 3, .tablespoon), (salt, nil, .toTaste)])
        func missing() throws -> Int? {
            try fixture.database.recipeCards(RecipeQuery(), limit: 1).rows.first?.missingCount
        }
        #expect(try missing() == 3)
        try fixture.database.setPantry(eggs.id, quantity: 2)
        try fixture.database.setPantry(salt.id, quantity: nil)
        #expect(try missing() == 2)
        #expect(try fixture.titles(RecipeQuery(maxMissing: 0)).isEmpty)
        try fixture.database.addToPantry([eggs.id: 1, milk.id: 1000])
        #expect(try missing() == 0)
        #expect(try fixture.titles(RecipeQuery(maxMissing: 0)) == ["Омлет"])

        // A dish for four needs six eggs.
        let pantry = try fixture.database.pantryItems(for: [eggs.id, milk.id, salt.id])
        let details = try #require(try fixture.database.recipe(id: omelette.recipe.id))
        #expect(details.availability(servings: 4, pantry: pantry).missingCount == 1)
    }

    @Test func aRecipesShortagesGoOnTheListAndGrowWithTheNextRecipe() throws {
        let fixture = try Fixture()
        let (eggs, milk, salt, _) = try products(fixture)
        let omelette = try fixture.addRecipe(
            "Омлет", [(eggs, 3, .piece), (milk, 3, .tablespoon), (salt, nil, .toTaste)])
        let pancakes = try fixture.addRecipe("Блины", [(eggs, 2, .piece), (milk, 0.5, .liter)])
        try fixture.database.setPantry(eggs.id, quantity: 1)
        try fixture.database.setPantry(salt.id, quantity: nil)

        try fixture.database.addShortages(ofRecipe: omelette.recipe.id)
        try fixture.database.addShortages(ofRecipe: pancakes.recipe.id)
        let list = try fixture.database.shopping(ShoppingQuery(), limit: 100).rows
        #expect(list.map(\.name) == ["Молоко", "Яйцо куриное"])
        let milkLine = try #require(list.first)
        #expect(milkLine.item.amount == 545)
        #expect(milkLine.item.unit == .milliliter)
        #expect(milkLine.item.reasons.map(\.title) == ["Омлет", "Блины"])
        // One egg at home: two for the omelette, then one more for the pancakes.
        #expect(list.last?.item.amount == 3)

        let forPancakes = ShoppingQuery(recipeID: pancakes.recipe.id)
        #expect(try fixture.database.shopping(forPancakes, limit: 100).total == 2)
        // Asked again for the same recipe, the list stays as it is.
        #expect(try fixture.database.addShortages(ofRecipe: omelette.recipe.id).isEmpty)
        #expect(try fixture.database.shopping(ShoppingQuery(), limit: 100).rows.first?.item.amount == 545)
    }

    @Test func linesThatDoNotAddUpStayApart() throws {
        let fixture = try Fixture()
        let (_, _, _, dill) = try products(fixture)
        try fixture.database.addToShopping([
            ShoppingAddition(product: dill.id, amount: 50, unit: .gram),
            ShoppingAddition(product: dill.id, amount: 1, unit: .bunch),
            ShoppingAddition(product: dill.id, amount: 0.1, unit: .kilogram),
            ShoppingAddition(text: "Батарейки", amount: 4),
            ShoppingAddition(text: "батарейки", amount: 2),
        ])
        let list = try fixture.database.shopping(ShoppingQuery(sort: [SortTerm(.createdAt)]), limit: 100).rows
        #expect(list.map(\.item.amount) == [150, 1, 6])
        #expect(list.map(\.name) == ["Укроп", "Укроп", "Батарейки"])
        #expect(throws: StoreError.self) { try fixture.database.addToShopping([ShoppingAddition(text: "  ")]) }
    }

    @Test func boughtItemsGoIntoThePantry() throws {
        let fixture = try Fixture()
        let (eggs, milk, _, _) = try products(fixture)
        let ids = try fixture.database.addToShopping([
            ShoppingAddition(product: eggs.id, amount: 10),
            ShoppingAddition(product: milk.id, amount: 1, unit: .liter),
            ShoppingAddition(text: "Хлеб"),
        ])
        try fixture.database.setChecked(true, items: Set(ids))
        let checked = try fixture.database.shopping(ShoppingQuery(isChecked: true), limit: 100).rows
        #expect(checked.count == 3)
        let amounts = Dictionary(uniqueKeysWithValues: checked.map { ($0.id, $0.amountInBaseUnit) })
        #expect(amounts[ids[1]] == 1000)

        try fixture.database.stockBought(amounts)
        #expect(try fixture.database.shopping(ShoppingQuery(), limit: 100).total == 0)
        let pantry = try fixture.database.pantryItems(for: [eggs.id, milk.id])
        #expect(pantry[eggs.id]?.quantity == 10)
        #expect(pantry[milk.id]?.quantity == 1000)
    }

    @Test func boughtItemsCanStayOnTheListPutAway() throws {
        let fixture = try Fixture()
        let (eggs, _, _, _) = try products(fixture)
        let ids = try fixture.database.addToShopping([ShoppingAddition(product: eggs.id, amount: 6)])
        try fixture.database.stockBought([ids[0]: 6], keepOnList: true)
        try fixture.database.stockBought([ids[0]: 6], keepOnList: true)
        #expect(try fixture.database.pantryItem(productID: eggs.id)?.quantity == 6)
        let item = try #require(try fixture.database.shopping(ShoppingQuery(), limit: 1).rows.first?.item)
        #expect(item.isChecked)
        #expect(item.stockedAt != nil)
        #expect(try fixture.database.clearChecked() == 1)
    }

    @Test func boughtItemsComeLastAndTheManualOrderHolds() throws {
        let fixture = try Fixture()
        let (eggs, milk, salt, dill) = try products(fixture)
        let ids = try fixture.database.addToShopping(
            [eggs, milk, salt, dill].map { ShoppingAddition(product: $0.id) } + [ShoppingAddition(text: "Свечи")])
        func names(_ query: ShoppingQuery) throws -> [String] {
            try fixture.database.shopping(query, limit: 100).rows.map(\.name)
        }
        // The aisles in the shop's order; text without an aisle at the end.
        #expect(try names(ShoppingQuery()) == ["Укроп", "Молоко", "Яйцо куриное", "Соль", "Свечи"])
        try fixture.database.setChecked(true, items: [ids[2]])
        #expect(try names(ShoppingQuery()) == ["Укроп", "Молоко", "Яйцо куриное", "Свечи", "Соль"])
        try fixture.database.reorderShopping([ids[4], ids[0]])
        #expect(
            try names(ShoppingQuery(sort: [SortTerm(.manual)])) == ["Свечи", "Яйцо куриное", "Молоко", "Укроп", "Соль"])
        #expect(try names(ShoppingQuery(text: "молок")) == ["Молоко"])
        #expect(try names(ShoppingQuery(text: "свеч")) == ["Свечи"])
        #expect(try names(ShoppingQuery(isChecked: false)).count == 4)
    }

    @Test func mergingProductsCarriesThePantryAndTheList() throws {
        let fixture = try Fixture()
        let (eggs, _, _, _) = try products(fixture)
        var duplicate = try fixture.add("Яйца С0")
        duplicate.baseUnit = .piece
        duplicate = try fixture.database.save(duplicate)
        try fixture.database.setPantry(eggs.id, quantity: 4)
        try fixture.database.setPantry(duplicate.id, quantity: 6)
        try fixture.database.addToShopping([ShoppingAddition(product: duplicate.id, amount: 10)])
        try fixture.database.mergeProduct(duplicate.id, into: eggs.id)
        #expect(try fixture.database.pantryItem(productID: eggs.id)?.quantity == 10)
        #expect(try fixture.database.shopping(ShoppingQuery(), limit: 10).rows.map(\.name) == ["Яйцо куриное"])
    }

    @Test func aNewBaseUnitConvertsWhatIsAtHome() throws {
        let fixture = try Fixture()
        var onions = try fixture.add("Лук")
        onions.gramsPerPiece = 100
        onions = try fixture.database.save(onions)
        try fixture.database.setPantry(onions.id, quantity: 500)
        onions.baseUnit = .piece
        onions = try fixture.database.save(onions)
        #expect(try fixture.database.pantryItem(productID: onions.id)?.quantity == 5)
        onions.baseUnit = .milliliter
        try fixture.database.save(onions)
        // No density: the five onions are there, uncounted.
        let item = try #require(try fixture.database.pantryItem(productID: onions.id))
        #expect(item.quantity == nil)
        #expect(item.isInStock)
    }
}

struct PantryMinimumTests {
    @Test func belowWhatIsKeptAtHomeTheRestGoesOnTheList() throws {
        let fixture = try Fixture()
        var eggs = try fixture.add("Яйцо куриное", aisle: "Молочное")
        eggs.baseUnit = .piece
        eggs = try fixture.database.save(eggs)
        try fixture.database.setPantry(eggs.id, quantity: 12)
        try fixture.database.setPantryMinimum(10, productID: eggs.id)
        #expect(try fixture.database.pantryItem(productID: eggs.id)?.status == .inStock)
        #expect(try fixture.database.shopping(ShoppingQuery(), limit: 10).total == 0)

        try fixture.database.takeFromPantry([eggs.id: 5])
        #expect(try fixture.database.pantryItem(productID: eggs.id)?.status == .low)
        var list = try fixture.database.shopping(ShoppingQuery(), limit: 10).rows
        #expect(list.map(\.item.amount) == [3])
        #expect(list.first?.item.reasons == [AppDatabase.keepAtHome])

        // Lower still: the same line says what is missing now.
        try fixture.database.takeFromPantry([eggs.id: 4])
        list = try fixture.database.shopping(ShoppingQuery(), limit: 10).rows
        #expect(list.map(\.item.amount) == [7])
        #expect(try fixture.database.pantry(PantryQuery(statuses: [.low]), limit: 10).total == 1)

        // Enough again: the line goes.
        try fixture.database.addToPantry([eggs.id: 10])
        #expect(try fixture.database.shopping(ShoppingQuery(), limit: 10).total == 0)
        try fixture.database.setPantryMinimum(nil, productID: eggs.id)
        #expect(try fixture.database.pantryItem(productID: eggs.id)?.minimum == nil)
    }
}
