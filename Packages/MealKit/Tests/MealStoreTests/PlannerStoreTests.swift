import Foundation
import GRDB
import MealCore
import Testing

@testable import MealStore

struct PlannerStoreTests {
    private let monday = Day(year: 2026, month: 10, day: 19)

    private func setUp() throws -> (Fixture, eggs: Product, milk: Product, omelette: RecipeDetails, meals: [MealType]) {
        let fixture = try Fixture()
        var eggs = try fixture.add("Яйцо куриное", aisle: "Молочное", kcal: 143, protein: 12.6, fat: 9.5, carbs: 0.7)
        eggs.baseUnit = .piece
        eggs.gramsPerPiece = 50
        eggs = try fixture.database.save(eggs)
        var milk = try fixture.add("Молоко", aisle: "Молочное", kcal: 60, protein: 3, fat: 3.2, carbs: 4.7)
        milk.baseUnit = .milliliter
        milk.density = 1
        milk = try fixture.database.save(milk)
        let omelette = try fixture.addRecipe("Омлет", [(eggs, 3, .piece), (milk, 100, .milliliter)])
        return (fixture, eggs, milk, omelette, try fixture.database.mealTypes())
    }

    @Test func dishesArePlannedMovedCopiedAndRemoved() throws {
        let (fixture, _, _, omelette, meals) = try setUp()
        let database = fixture.database
        let breakfast = meals[0].id
        let dinner = meals[2].id
        let first = try database.planMeal(on: monday, meal: breakfast, recipe: omelette.recipe.id)
        #expect(first.servings == 2)
        let guests = try database.planMeal(on: monday, meal: breakfast, text: "  Завтрак в кафе ")
        #expect(guests.text == "Завтрак в кафе")
        let third = try database.planMeal(on: monday, meal: breakfast, recipe: omelette.recipe.id, servings: 4)

        // Before the first: the cafe goes up.
        try database.movePlanEntry(guests.id, to: monday, meal: breakfast, before: first.id)
        var week = try database.weekPlan(starting: monday)
        #expect(week.entries(on: monday, meal: breakfast).map(\.id) == [guests.id, first.id, third.id])

        try database.movePlanEntry(third.id, to: monday.adding(days: 2), meal: dinner)
        let copy = try database.copyPlanEntry(first.id, to: monday.adding(days: 4), meal: dinner)
        week = try database.weekPlan(starting: monday)
        #expect(week.entries(on: monday.adding(days: 2), meal: dinner).map(\.servings) == [4])
        #expect(week.entries(on: monday.adding(days: 4), meal: dinner).map(\.id) == [copy.id])
        #expect(week.recipes[omelette.recipe.id]?.recipe.title == "Омлет")
        #expect(week.mealTypes.map(\.name) == ["Завтрак", "Обед", "Ужин", "Перекус"])

        try database.setPlanServings(3, entry: copy.id)
        #expect(try database.planEntry(id: copy.id)?.servings == 3)
        #expect(throws: StoreError.self) { try database.setPlanServings(0, entry: copy.id) }
        try database.removePlanEntries([copy.id, guests.id])
        #expect(try database.weekPlan(starting: monday).entries.count == 2)
        #expect(throws: StoreError.self) { try database.planMeal(on: monday, meal: breakfast, text: " ") }
        // Another week does not see these.
        #expect(try database.weekPlan(starting: monday.adding(days: 7)).entries.isEmpty)
    }

    @Test func aWeekIsCopiedAsPlanned() throws {
        let (fixture, eggs, _, omelette, meals) = try setUp()
        let database = fixture.database
        try database.setPantry(eggs.id, quantity: 10)
        let cooked = try database.planMeal(on: monday.adding(days: 1), meal: meals[0].id, recipe: omelette.recipe.id)
        try database.planMeal(on: monday.adding(days: 6), meal: meals[2].id, text: "Ужин в гостях")
        try database.markCooked(cooked.id, using: [eggs.id: 3])
        #expect(try database.copyWeek(from: monday, to: monday.adding(days: 7)) == 2)
        let next = try database.weekPlan(starting: monday.adding(days: 7))
        #expect(next.entries.map(\.day) == [monday.adding(days: 8), monday.adding(days: 13)])
        #expect(next.entries.allSatisfy { !$0.isCooked })
    }

    @Test func cookingTakesFromThePantryAndUndoGivesItBack() throws {
        let (fixture, eggs, milk, omelette, meals) = try setUp()
        let database = fixture.database
        try database.setPantry(eggs.id, quantity: 10)
        try database.setPantry(milk.id, quantity: nil)
        let entry = try database.planMeal(on: monday, meal: meals[0].id, recipe: omelette.recipe.id, servings: 4)
        let use = try database.cookingUse(of: entry.id)
        // Milk is uncounted: nothing to take.
        #expect(use.map(\.product.name) == ["Яйцо куриное"])
        #expect(use.first?.amount == 6)

        try database.markCooked(entry.id, using: [eggs.id: 5])
        #expect(try database.pantryItem(productID: eggs.id)?.quantity == 5)
        #expect(try database.planEntry(id: entry.id)?.isCooked == true)
        #expect(throws: StoreError.self) { try database.markCooked(entry.id, using: [:]) }
        let card = try #require(try database.recipeCards(RecipeQuery(), limit: 1).rows.first)
        #expect(card.lastCookedAt != nil)

        try database.undoCooked(entry.id)
        #expect(try database.pantryItem(productID: eggs.id)?.quantity == 10)
        #expect(try database.planEntry(id: entry.id)?.isCooked == false)
        #expect(try database.recipeCards(RecipeQuery(), limit: 1).rows.first?.lastCookedAt == nil)
    }

    @Test func recipesNotCookedForLongestComeFirst() throws {
        let (fixture, eggs, _, omelette, meals) = try setUp()
        let database = fixture.database
        try fixture.addRecipe("Яичница", [(eggs, 2, .piece)])
        let entry = try database.planMeal(on: monday, meal: meals[0].id, recipe: omelette.recipe.id)
        try database.markCooked(entry.id, using: [:])
        #expect(try fixture.titles(RecipeQuery(sort: [SortTerm(.lastCooked)])) == ["Яичница", "Омлет"])
        #expect(try fixture.titles(RecipeQuery(sort: [SortTerm(.lastCooked, .descending)])) == ["Омлет", "Яичница"])
    }

    @Test func theWeeksShortagesGoOnTheListOnceWithTheirDays() throws {
        let (fixture, eggs, milk, omelette, meals) = try setUp()
        let database = fixture.database
        try database.setPantry(eggs.id, quantity: 4)
        try database.planMeal(on: monday, meal: meals[0].id, recipe: omelette.recipe.id)
        try database.planMeal(on: monday.adding(days: 3), meal: meals[0].id, recipe: omelette.recipe.id)
        try database.addMenuShortages(week: monday, from: monday)
        try database.addMenuShortages(week: monday, from: monday)
        let list = try database.shopping(ShoppingQuery(), limit: 10).rows
        #expect(list.map(\.name) == ["Молоко", "Яйцо куриное"])
        #expect(list.map(\.item.amount) == [200, 2])
        #expect(Set(list[0].item.reasons.compactMap(\.day)) == ["2026-10-19", "2026-10-22"])
        #expect(try database.shopping(ShoppingQuery(day: "2026-10-22"), limit: 10).total == 2)

        let needed = PantryQuery(menuDays: monday...monday.adding(days: 6))
        #expect(try database.pantry(needed, limit: 10).rows.map(\.product.name) == ["Яйцо куриное"])
        try database.setPantry(milk.id, quantity: 0)
        #expect(try database.pantry(needed, limit: 10).rows.map(\.product.name) == ["Молоко", "Яйцо куриное"])
    }

    @Test func mealsAreAddedRenamedAndDeleted() throws {
        let (fixture, _, _, omelette, _) = try setUp()
        let database = fixture.database
        let second = try database.newMealType(named: "Второй завтрак")
        #expect(try database.mealTypes().last?.name == "Второй завтрак")
        #expect(throws: StoreError.self) { try database.newMealType(named: "обед") }
        var renamed = second
        renamed.name = "Полдник"
        renamed.color = .orange
        #expect(try database.save(renamed).name == "Полдник")
        try database.planMeal(on: monday, meal: second.id, recipe: omelette.recipe.id)
        try database.reorderMealTypes([second.id] + (try database.mealTypes().map(\.id).filter { $0 != second.id }))
        #expect(try database.mealTypes().first?.name == "Полдник")
        try database.deleteMealType(id: second.id)
        #expect(try database.weekPlan(starting: monday).entries.isEmpty)
    }
}
