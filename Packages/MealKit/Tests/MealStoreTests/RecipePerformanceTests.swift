import Foundation
import GRDB
import MealCore
import Testing

@testable import MealStore

/// The recipe lists' budget on 5 000 recipes of eight ingredients each, in a database file with the starting
/// product base: the first block under 50 ms, a search keystroke, a new order or filter under 100 ms.
/// Meaningful only in an optimized build: `make perf`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEAL_PERF"] == "1"))
struct RecipePerformanceTests {
    private static let recipes = 5_000
    private static let dishes = [
        "Омлет", "Суп с курицей", "Салат овощной", "Каша овсяная", "Паста с сыром", "Плов", "Сырники", "Борщ",
        "Котлеты", "Запеканка", "Рагу", "Блины",
    ]

    private static func database() throws -> (AppDatabase, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "meal recipes perf \(UUID().uuidString)", directoryHint: .isDirectory)
        let database = try AppDatabase.open(in: folder)
        let products = try database.products(ProductQuery(), limit: 1000).rows
        let categories = try (0..<12).map { try database.newCategory(named: "Категория \($0)") }
        try database.writer.write { db in
            var ids: [Int64] = []
            for index in 0..<recipes {
                var recipe = RecipeRecord(
                    Recipe(
                        id: 0, title: "\(dishes[index % dishes.count]) \(index)", servings: 1 + index % 4,
                        cookMinutes: 10 + index % 80, isFavorite: index % 9 == 0),
                    id: nil)
                try recipe.insert(db)
                let id = recipe.id ?? 0
                ids.append(id)
                for line in 0..<8 {
                    let product = products[(index * 7 + line * 13) % products.count]
                    var row = RecipeIngredientRecord(
                        RecipeIngredient(productID: product.id, amount: Double(20 + line * 15), unit: .gram),
                        recipeID: id, position: line)
                    try row.insert(db)
                }
                var step = RecipeStepRecord(recipeId: id, position: 0, text: "Смешать и готовить \(index % 30) минут")
                try step.insert(db)
                try RecipeCategoryRecord(recipeId: id, categoryId: categories[index % categories.count].id).insert(db)
                if index % 5 == 0 {
                    try RecipeCategoryRecord(recipeId: id, categoryId: categories[(index + 1) % categories.count].id)
                        .insert(db)
                }
            }
            try RecipeDerived.refresh(db, recipeIDs: ids)
        }
        return (database, folder)
    }

    private func milliseconds(_ work: () throws -> Void) rethrows -> Double {
        var runs: [Duration] = []
        for _ in 0..<5 {
            let start = ContinuousClock.now
            try work()
            runs.append(ContinuousClock.now - start)
        }
        let median = runs.sorted()[2]
        return Double(median.components.seconds) * 1000 + Double(median.components.attoseconds) / 1e15
    }

    @Test func listsStayWithinBudget() throws {
        let (database, folder) = try Self.database()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(try database.recipeCards(RecipeQuery(), limit: 1).total == Self.recipes)
        let category = try #require(try database.categories().first)
        let egg = try #require(try database.product(named: "Яйцо куриное"))

        let gallery = try milliseconds { _ = try database.recipeGallery(RecipeGalleryQuery(), limit: 100) }
        print("gallery first block: \(gallery) ms")
        #expect(gallery < 50)
        let table = try milliseconds { _ = try database.recipeCards(RecipeQuery(), limit: 100) }
        print("table first block: \(table) ms")
        #expect(table < 50)
        let groups = try milliseconds { _ = try database.reader.read { try RecipeListSQL.groups($0, RecipeQuery()) } }
        print("group counts: \(groups) ms")
        #expect(groups < 100)

        for text in ["о", "ом", "омлет", "яйц", "суп с кур", "картошка"] {
            let search = try milliseconds { _ = try database.recipeCards(RecipeQuery(text: text), limit: 100) }
            print("search «\(text)»: \(search) ms")
            #expect(search < 100, "«\(text)»")
        }
        for key in [RecipeQuery.SortKey.kcalPerServing, .protein, .totalTime, .createdAt] {
            let sorted = try milliseconds {
                _ = try database.recipeGallery(
                    RecipeGalleryQuery(recipes: RecipeQuery(sort: [SortTerm(key, .descending)])), limit: 100)
            }
            print("gallery by \(key): \(sorted) ms")
            #expect(sorted < 100)
        }
        let filtered = try milliseconds {
            _ = try database.recipeCards(
                RecipeQuery(
                    text: "суп", categoryIDs: [category.id], withProducts: [egg.id],
                    kcalPerServing: ValueRange(max: 600), maxMinutes: 60, sort: [SortTerm(.protein, .descending)]),
                limit: 100)
        }
        print("search, filters and order: \(filtered) ms")
        #expect(filtered < 100)
    }
}
