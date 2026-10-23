import Foundation
import MealCore
import Testing

struct DayTests {
    @Test func daysReadWriteAndCount() throws {
        let day = try #require(Day("2026-10-23"))
        #expect(day.description == "2026-10-23")
        #expect(day.weekday == 5)
        #expect(day.weekStart == Day(year: 2026, month: 10, day: 19))
        #expect(day.weekNumber == 43)
        #expect(day.adding(days: 9) == Day(year: 2026, month: 11, day: 1))
        #expect(Day(year: 2026, month: 10, day: 25).weekStart == Day(year: 2026, month: 10, day: 19))
        #expect(Day(year: 2026, month: 10, day: 26).weekStart == Day(year: 2026, month: 10, day: 26))
        #expect(Day("2026-02-30") == nil)
        #expect(Day("завтра") == nil)
        #expect(Day(year: 2026, month: 1, day: 1) < day)
        // Across the change to winter time, the last Sunday of October.
        #expect(Day(year: 2026, month: 10, day: 24).adding(days: 2) == Day(year: 2026, month: 10, day: 26))
        let encoded = try JSONEncoder().encode([day])
        #expect(String(decoding: encoded, as: UTF8.self) == #"["2026-10-23"]"#)
        #expect(try JSONDecoder().decode([Day].self, from: encoded) == [day])
    }
}

/// A reference week: what the menu needs and what to buy, counted by hand.
struct WeekPlanTests {
    private let egg = Product(
        id: 1, name: "Яйцо куриное", kcal: 143, protein: 12.6, fat: 9.5, carbs: 0.7, baseUnit: .piece,
        gramsPerPiece: 50)
    private let milk = Product(
        id: 2, name: "Молоко", kcal: 60, protein: 3, fat: 3.2, carbs: 4.7, baseUnit: .milliliter, density: 1)
    private let flour = Product(id: 3, name: "Мука", kcal: 364, protein: 10, fat: 1, carbs: 76, density: 0.53)
    private let salt = Product(id: 4, name: "Соль", kcal: 0, protein: 0, fat: 0, carbs: 0, isStaple: true)
    private let dill = Product(id: 5, name: "Укроп", kcal: 43, protein: 3.5, fat: 1.1, carbs: 7)
    private let monday = Day(year: 2026, month: 10, day: 19)

    private var omelette: RecipeDetails {
        RecipeDetails(
            recipe: Recipe(id: 10, title: "Омлет", servings: 2),
            ingredients: [
                RecipeIngredient(productID: 1, amount: 3, unit: .piece),
                RecipeIngredient(productID: 2, amount: 100, unit: .milliliter),
                RecipeIngredient(productID: 4, unit: .toTaste),
                RecipeIngredient(productID: 5, amount: 1, unit: .bunch, isOptional: true),
            ],
            products: products)
    }

    private var pancakes: RecipeDetails {
        RecipeDetails(
            recipe: Recipe(id: 11, title: "Блины", servings: 4),
            ingredients: [
                RecipeIngredient(productID: 1, amount: 2, unit: .piece),
                RecipeIngredient(productID: 2, amount: 0.5, unit: .liter),
                RecipeIngredient(productID: 3, amount: 1, unit: .cup),
                RecipeIngredient(productID: 4, amount: 1, unit: .pinch),
            ],
            products: products)
    }

    private var products: [Product.ID: Product] {
        Dictionary(uniqueKeysWithValues: [egg, milk, flour, salt, dill].map { ($0.id, $0) })
    }

    private func plan(pantry: [PantryItem]) -> WeekPlan {
        WeekPlan(
            start: monday,
            entries: [
                PlanEntry(id: 1, day: monday, mealTypeID: 1, recipeID: 10, servings: 2),
                PlanEntry(id: 2, day: monday.adding(days: 1), mealTypeID: 1, recipeID: 11, servings: 2),
                PlanEntry(id: 3, day: monday.adding(days: 2), mealTypeID: 1, recipeID: 10, servings: 4),
                PlanEntry(id: 4, day: monday.adding(days: 2), mealTypeID: 3, text: "Ужин в гостях"),
            ],
            recipes: [10: omelette, 11: pancakes],
            pantry: Dictionary(uniqueKeysWithValues: pantry.map { ($0.productID, $0) }))
    }

    @Test func thePantryCoversTheWeekInOrderAndTheRestGoesToTheList() {
        let week = plan(pantry: [
            PantryItem(productID: 1, quantity: 6), PantryItem(productID: 2, quantity: 300),
            PantryItem(productID: 4, quantity: nil),
        ])
        let supply = week.supply(from: monday)
        // Monday, omelette for two: 3 eggs and 100 ml milk, covered; 3 eggs and 200 ml left. Tuesday, pancakes for
        // two of four: an egg, 250 ml milk — 50 ml short — and half a cup of flour, 66,25 g, none at home.
        // Wednesday, omelette for four: 6 eggs with 2 left — 4 short — and 200 ml milk, all short.
        #expect(supply.shortEntries == [2, 3])
        let byProduct = Dictionary(grouping: supply.shortages, by: { $0.productID ?? 0 })
            .mapValues { $0.compactMap(\.amount).reduce(0, +) }
        #expect(byProduct[1] == 4)
        #expect(byProduct[2] == 250)
        #expect(abs((byProduct[3] ?? 0) - 66.25) < 1e-9)
        #expect(byProduct[4] == nil)
        #expect(byProduct[5] == nil)
        #expect(supply.shortages.first?.reason == ShoppingReason(recipeID: 11, title: "Блины", day: "2026-10-20"))
    }

    @Test func daysStartingLaterLeaveTheEarlierOnesOut() {
        let week = plan(pantry: [])
        let fromWednesday = week.supply(from: monday.adding(days: 2))
        #expect(fromWednesday.shortEntries == [3])
        // Six eggs and 200 ml of milk, and salt to have at all.
        #expect(fromWednesday.shortages.map(\.amount) == [6, 200, nil])
        var cooked = week
        cooked.entries[2].cookedAt = .now
        #expect(cooked.supply(from: monday).shortEntries == [1, 2])
    }

    @Test func aDayAddsUpPerPersonAndAltogether() throws {
        let week = plan(pantry: [])
        let monday = week.nutrition(on: self.monday)
        let serving = try #require(omelette.nutrition.perServing)
        #expect(monday.perPerson == serving)
        #expect(monday.total.kcal == serving.kcal * 2)
        let wednesday = week.nutrition(on: self.monday.adding(days: 2))
        #expect(wednesday.counted == 1)
        #expect(wednesday.uncounted == 1)
        #expect(wednesday.total.kcal == serving.kcal * 4)
        #expect(week.nutrition(on: self.monday.adding(days: 5)).isEmpty)
        let average = try #require(week.averageDay)
        let pancakeServing = try #require(pancakes.nutrition.perServing)
        #expect(abs(average.perPerson.kcal - (serving.kcal * 2 + pancakeServing.kcal) / 3) < 1e-9)
    }

    @Test func cookingTakesWhatTheCountedProductsGive() {
        let pantry: [Product.ID: PantryItem] = [
            1: PantryItem(productID: 1, quantity: 10), 2: PantryItem(productID: 2, quantity: nil),
            4: PantryItem(productID: 4, quantity: nil), 3: PantryItem(productID: 3, quantity: 1000),
        ]
        let use = pancakes.cookingUse(servings: 8, pantry: pantry)
        // Uncounted milk and the staple salt take nothing.
        #expect(use.map(\.product.name) == ["Яйцо куриное", "Мука"])
        #expect(use.map(\.amount) == [4, 265])
        #expect(use.first?.atHome == 10)
    }
}
