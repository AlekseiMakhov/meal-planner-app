import MealCore
import Testing

struct SearchTextTests {
    @Test(arguments: [
        ("молоко", "молок"), ("молока", "молок"), ("молоком", "молок"),
        ("яйцо", "яйц"), ("яйца", "яйц"),
        ("лук", "лук"), ("лука", "лук"), ("луковица", "луковиц"),
        ("помидоров", "помидор"), ("помидоры", "помидор"),
        ("сливочное", "сливочн"), ("сливочного", "сливочн"),
        ("масло", "масл"), ("масла", "масл"),
        ("картофель", "картофел"), ("картофеля", "картофел"),
        ("соль", "сол"), ("соли", "сол"),
        ("свекла", "свекл"), ("свеклы", "свекл"),
        ("петрушка", "петрушк"), ("петрушки", "петрушк"),
        ("куриное", "курин"), ("куриного", "курин"),
        ("говядина", "говядин"), ("говядины", "говядин"),
        // Snowball reads «-на» after «а» as a verb ending; both forms still share the stem.
        ("сметана", "смета"), ("сметаны", "смета"),
        ("тертый", "терт"), ("нарезанный", "нареза"),
    ])
    func formsShareAStem(_ word: String, _ stem: String) {
        #expect(RussianStemmer.stem(word) == stem)
    }

    @Test func otherWordsStayAsTheyAre() {
        #expect(RussianStemmer.stem("usda") == "usda")
        #expect(RussianStemmer.stem("33") == "33")
        #expect(RussianStemmer.stem("ёж") == "ёж")
        #expect(RussianStemmer.stem("рис") == "рис")
    }

    @Test func normalizedIgnoresCaseYoAndPunctuation() {
        #expect(SearchText.normalized("Свёкла") == "свекла")
        #expect(SearchText.normalized("  Лук-порей,  молодой ") == "лук порей молодой")
        #expect(SearchText.normalized("Молоко 3,2%") == "молоко 3 2")
    }

    @Test func termsAreStemsOfTheQuery() {
        #expect(SearchText.terms("Сливочного масла") == ["сливочн", "масл"])
        #expect(SearchText.terms("свёклы") == ["свекл"])
        #expect(SearchText.terms("3,2") == ["3", "2"])
        #expect(SearchText.terms("  ") == [])
    }
}

struct ProductTests {
    @Test func tidyingTrimsTheNameAndDropsRepeatedAliases() {
        let product = Product(id: 1, name: "  Яйцо куриное ", aliases: ["яйца", " Яйца", "", "яйцо куриное", "яиц "])
            .tidied()
        #expect(product.name == "Яйцо куриное")
        #expect(product.aliases == ["яйца", "яиц"])
        #expect(product.searchText == "яйцо куриное яйца яиц")
    }

    @Test func nutritionIsCompleteOnlyWithAllFourValues() {
        var product = Product(id: 1, name: "Молоко", kcal: 61, protein: 3.15, fat: 3.25)
        #expect(product.nutrition == nil)
        product.carbs = 4.8
        #expect(product.nutrition?.kcal == 61)
        product.nutrition = nil
        #expect(product.kcal == nil && product.carbs == nil)
    }

    @Test func problemsExplainWhatCannotBeSaved() {
        #expect(Product(id: 1, name: "Сахар", kcal: 387, protein: 0, fat: 0, carbs: 99.98).problems.isEmpty)
        #expect(Product(id: 1, name: "  ").problems.map(\.description) == ["Нужно название."])
        #expect(Product(id: 1, name: "Масло", kcal: 1200).problems.count == 1)
        #expect(Product(id: 1, name: "Каша", protein: 60, fat: 30, carbs: 20).problems.count == 1)
        #expect(Product(id: 1, name: "Яйцо", gramsPerPiece: 0).problems.count == 1)
        #expect(Product(id: 1, name: "Мёд", density: 9).problems.count == 1)
        #expect(Product(id: 1, name: "Укроп", density: 0.038).problems.isEmpty)
        #expect(Product(id: 1, name: "Чеснок", namedUnits: [.clove: -1]).problems.count == 1)
    }
}
