import Foundation
import MealCore
import Testing

@testable import MealStore

struct ProductQueryTests {
    // MARK: - Search

    @Test func searchIgnoresCaseAndYo() throws {
        let fixture = try Fixture()
        try fixture.add("Свёкла")
        try fixture.add("Морковь")
        #expect(try fixture.names(ProductQuery(text: "свекла")) == ["Свёкла"])
        #expect(try fixture.names(ProductQuery(text: "СВЁКЛ")) == ["Свёкла"])
    }

    @Test func searchFindsOtherFormsOfAWord() throws {
        let fixture = try Fixture()
        try fixture.add("Молоко 3,2%")
        try fixture.add("Масло сливочное")
        try fixture.add("Яйцо куриное")
        try fixture.add("Лук репчатый")
        try fixture.add("Сметана 15%")
        #expect(try fixture.names(ProductQuery(text: "молока")) == ["Молоко 3,2%"])
        #expect(try fixture.names(ProductQuery(text: "сливочного масла")) == ["Масло сливочное"])
        #expect(try fixture.names(ProductQuery(text: "яйца")) == ["Яйцо куриное"])
        #expect(try fixture.names(ProductQuery(text: "лука")) == ["Лук репчатый"])
        #expect(try fixture.names(ProductQuery(text: "сметаны")) == ["Сметана 15%"])
        #expect(try fixture.names(ProductQuery(text: "сметана 15")) == ["Сметана 15%"])
    }

    @Test func searchFindsAliasesAndPrefixes() throws {
        let fixture = try Fixture()
        try fixture.add("Картофель", aliases: ["картошка"])
        try fixture.add("Капуста")
        #expect(try fixture.names(ProductQuery(text: "картошку")) == ["Картофель"])
        #expect(try fixture.names(ProductQuery(text: "ка")) == ["Капуста", "Картофель"])
        #expect(try fixture.names(ProductQuery(text: "  ")).count == 2)
        #expect(try fixture.names(ProductQuery(text: "\"*")).count == 2)
    }

    @Test func everyWordOfTheSearchMustMatch() throws {
        let fixture = try Fixture()
        try fixture.add("Масло сливочное")
        try fixture.add("Масло оливковое")
        #expect(try fixture.names(ProductQuery(text: "масло олив")) == ["Масло оливковое"])
    }

    // MARK: - Filters

    @Test func filterByAisle() throws {
        let fixture = try Fixture()
        try fixture.add("Морковь", aisle: "Овощи")
        try fixture.add("Кефир", aisle: "Молочное")
        try fixture.add("Без отдела")
        let vegetables = try #require(fixture.aisles["Овощи"])
        let dairy = try #require(fixture.aisles["Молочное"])
        #expect(try fixture.names(ProductQuery(aisleIDs: [vegetables])) == ["Морковь"])
        #expect(try fixture.names(ProductQuery(aisleIDs: [vegetables, dairy])) == ["Кефир", "Морковь"])
    }

    @Test func filterByStaple() throws {
        let fixture = try Fixture()
        try fixture.add("Соль", staple: true)
        try fixture.add("Морковь")
        #expect(try fixture.names(ProductQuery(isStaple: true)) == ["Соль"])
        #expect(try fixture.names(ProductQuery(isStaple: false)) == ["Морковь"])
    }

    @Test func filterByNutritionState() throws {
        let fixture = try Fixture()
        try fixture.add("Полный", kcal: 100, protein: 1, fat: 1, carbs: 20)
        try fixture.add("Без углеводов", kcal: 100, protein: 1, fat: 1)
        try fixture.add("Пустой")
        try fixture.add("Сомнительный", kcal: 100, protein: 1, fat: 1, carbs: 20, review: true)
        #expect(try fixture.names(ProductQuery(nutrition: .complete)) == ["Полный", "Сомнительный"])
        #expect(try fixture.names(ProductQuery(nutrition: .missing)) == ["Без углеводов", "Пустой"])
        #expect(try fixture.names(ProductQuery(nutrition: .needsReview)) == ["Сомнительный"])
    }

    @Test func filterByCalories() throws {
        let fixture = try Fixture()
        try fixture.add("Огурец", kcal: 15)
        try fixture.add("Банан", kcal: 89)
        try fixture.add("Сахар", kcal: 387)
        try fixture.add("Неизвестно")
        #expect(try fixture.names(ProductQuery(kcal: ValueRange(min: 50))) == ["Банан", "Сахар"])
        #expect(try fixture.names(ProductQuery(kcal: ValueRange(max: 89))) == ["Банан", "Огурец"])
        #expect(try fixture.names(ProductQuery(kcal: ValueRange(min: 16, max: 100))) == ["Банан"])
    }

    @Test func filterBySource() throws {
        let fixture = try Fixture()
        try fixture.add("Из USDA", source: .usda)
        try fixture.add("С упаковки", source: .label)
        try fixture.add("Ниоткуда")
        #expect(try fixture.names(ProductQuery(sources: [.usda])) == ["Из USDA"])
        #expect(try fixture.names(ProductQuery(sources: [.usda, .label])) == ["Из USDA", "С упаковки"])
    }

    @Test func filtersCombineWithSearch() throws {
        let fixture = try Fixture()
        try fixture.add("Масло сливочное", aisle: "Молочное", kcal: 717)
        try fixture.add("Масло оливковое", kcal: 884)
        try fixture.add("Молоко", aisle: "Молочное", kcal: 61)
        let dairy = try #require(fixture.aisles["Молочное"])
        #expect(try fixture.names(ProductQuery(text: "масло", aisleIDs: [dairy])) == ["Масло сливочное"])
        #expect(try fixture.database.products(ProductQuery(text: "масло", aisleIDs: [dairy]), limit: 10).total == 1)
        #expect(ProductQuery(text: "масло", aisleIDs: [dairy], kcal: ValueRange(min: 1)).filterCount == 2)
        #expect(ProductQuery(text: "масло", aisleIDs: [dairy]).withoutFilters == ProductQuery(text: "масло"))
    }

    // MARK: - Order

    @Test func equalValuesKeepTheirOrderByName() throws {
        let fixture = try Fixture()
        try fixture.add("Вишня", kcal: 50)
        try fixture.add("Абрикос", kcal: 50)
        try fixture.add("Ёжевика", kcal: 50)
        try fixture.add("Банан", kcal: 89)
        try fixture.add("Без данных")
        #expect(
            try fixture.names(ProductQuery(sort: [SortTerm(.kcal)]))
                == ["Абрикос", "Вишня", "Ёжевика", "Банан", "Без данных"])
        #expect(
            try fixture.names(ProductQuery(sort: [SortTerm(.kcal, .descending)]))
                == ["Банан", "Абрикос", "Вишня", "Ёжевика", "Без данных"])
    }

    @Test func orderByAisleFollowsTheShop() throws {
        let fixture = try Fixture()
        try fixture.add("Соль", aisle: "Специи")
        try fixture.add("Морковь", aisle: "Овощи")
        try fixture.add("Кефир", aisle: "Молочное")
        try fixture.add("Без отдела")
        #expect(
            try fixture.names(ProductQuery(sort: [SortTerm(.aisle)])) == ["Морковь", "Кефир", "Соль", "Без отдела"])
        #expect(
            try fixture.names(ProductQuery(sort: [SortTerm(.aisle, .descending)]))
                == ["Соль", "Кефир", "Морковь", "Без отдела"])
    }

    @Test func orderByNameIgnoresCaseAndYo() throws {
        let fixture = try Fixture()
        try fixture.add("ёлочные игрушки")
        try fixture.add("Ешки")
        try fixture.add("Ж")
        try fixture.add("Д")
        #expect(try fixture.names(ProductQuery()) == ["Д", "ёлочные игрушки", "Ешки", "Ж"])
    }

    @Test func orderByDateAdded() throws {
        let fixture = try Fixture()
        try fixture.add("Старый", created: Date(timeIntervalSince1970: 1_000))
        try fixture.add("Новый", created: Date(timeIntervalSince1970: 2_000))
        #expect(try fixture.names(ProductQuery(sort: [SortTerm(.createdAt, .descending)])) == ["Новый", "Старый"])
    }

    @Test func relevanceWithoutASearchIsTheName() throws {
        let fixture = try Fixture()
        try fixture.add("Б")
        try fixture.add("А")
        #expect(try fixture.names(ProductQuery(sort: [SortTerm(.relevance)])) == ["А", "Б"])
        #expect(try fixture.names(ProductQuery(text: "а", sort: [SortTerm(.relevance)])) == ["А"])
    }

    @Test func blocksJoinIntoTheWholeList() throws {
        let fixture = try Fixture()
        for index in 0..<30 {
            try fixture.add("Продукт \(index)", kcal: Double(index % 4) * 10)
        }
        let query = ProductQuery(sort: [SortTerm(.kcal, .descending)])
        let whole = try fixture.names(query, limit: 100)
        #expect(try fixture.names(query, limit: 10) == Array(whole.prefix(10)))
        #expect(try fixture.names(query, limit: 20) == Array(whole.prefix(20)))
        #expect(try fixture.database.products(query, limit: 10).total == 30)
    }
}
