import MealCore
import Testing

/// Lines as Russian recipes write them, from sites, books and the Notion base the app replaces.
struct IngredientParserTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let line: String
        let expected: [ParsedIngredient]

        var testDescription: String {
            line
        }
    }

    private static func line(
        _ line: String, _ name: String, _ amount: Double? = nil, _ unit: MeasureUnit? = nil, max: Double? = nil,
        note: String? = nil, optional: Bool = false
    ) -> Case {
        Case(
            line: line,
            expected: [
                ParsedIngredient(
                    name: name, amount: amount, amountMax: max, unit: unit, note: note, isOptional: optional)
            ])
    }

    private static func several(_ line: String, _ names: [String], unit: MeasureUnit?, optional: Bool = false) -> Case {
        Case(
            line: line,
            expected: names.map {
                ParsedIngredient(
                    name: $0, unit: unit, note: optional ? "по желанию" : nil, isOptional: optional)
            })
    }

    static let cases: [Case] = [
        // Name first, then the amount.
        line("Молоко — 3 ст. л.", "Молоко", 3, .tablespoon),
        line("Яйца — 3 шт.", "Яйца", 3, .piece),
        line("Фета — 40 гр.", "Фета", 40, .gram),
        line("Сливочное масло 82,5% — 50 г", "Сливочное масло 82,5%", 50, .gram),
        line("Помидоры черри — 10 шт.", "Помидоры черри", 10, .piece),
        line("Вода — 200-250 мл", "Вода", 200, .milliliter, max: 250),
        line("Молоко 3,2% — 500 мл", "Молоко 3,2%", 500, .milliliter),
        line("Мука пшеничная — 2 стакана", "Мука пшеничная", 2, .cup),
        line("Сахар — 1 ст. ложка", "Сахар", 1, .tablespoon),
        line("Разрыхлитель — 1 пакетик", "Разрыхлитель", 1, .pack),
        line("Куриное филе — 500 г", "Куриное филе", 500, .gram),
        line("Фарш говяжий 400 гр", "Фарш говяжий", 400, .gram),
        line("Лавровый лист — 2 шт.", "Лавровый лист", 2, .piece),
        line("Чеснок — 3 зубчика", "Чеснок", 3, .clove),
        line("Мёд — 2 ч. л.", "Мёд", 2, .teaspoon),
        line("Дрожжи сухие — 11 г", "Дрожжи сухие", 11, .gram),
        line("Мука — 250–300 г", "Мука", 250, .gram, max: 300),
        line("Сливки 33% — 200 мл", "Сливки 33%", 200, .milliliter),
        line("Кинза — 1/2 пучка", "Кинза", 0.5, .bunch),
        line("Помидоры — 2-3 шт.", "Помидоры", 2, .piece, max: 3),
        line("Огурцы солёные — 2 шт.", "Огурцы солёные", 2, .piece),
        line("Шампиньоны — 300 г", "Шампиньоны", 300, .gram),
        line("Рис — 1 стакан", "Рис", 1, .cup),
        line("Сметана 15% — 2 ст.л.", "Сметана 15%", 2, .tablespoon),
        line("Соевый соус — 2 ст.л.", "Соевый соус", 2, .tablespoon),
        line("Лимонный сок — 1 ч.л.", "Лимонный сок", 1, .teaspoon),
        line("Желатин: 10 г", "Желатин", 10, .gram),
        line("Сахар — полтора стакана", "Сахар", 1.5, .cup),
        line("Картофель — 4 шт. среднего размера", "Картофель", 4, .piece, note: "среднего размера"),
        line("Тыква 500 г, очищенная", "Тыква", 500, .gram, note: "очищенная"),
        line("Сыр пармезан — 30 г, тёртый", "Сыр пармезан", 30, .gram, note: "тёртый"),
        line("Яйцо — 1 шт. + 1 желток", "Яйцо", 1, .piece, note: "1 желток"),
        // The amount first, then the product in the genitive.
        line("3 ст. л. молока", "молока", 3, .tablespoon),
        line("3 яйца", "яйца", 3, .piece),
        line("1,5 кг картофеля", "картофеля", 1.5, .kilogram),
        line("2–3 зубчика чеснока", "чеснока", 2, .clove, max: 3),
        line("1/2 стакана сахара", "сахара", 0.5, .cup),
        line("½ ч. л. соды", "соды", 0.5, .teaspoon),
        line("1½ стакана муки", "муки", 1.5, .cup),
        line("40 г феты", "феты", 40, .gram),
        line("1 л молока", "молока", 1, .liter),
        line("2 столовые ложки оливкового масла", "оливкового масла", 2, .tablespoon),
        line("1 чайная ложка разрыхлителя", "разрыхлителя", 1, .teaspoon),
        line("100гр сыра", "сыра", 100, .gram),
        line("0.5 кг говядины", "говядины", 0.5, .kilogram),
        line("2 лавровых листа", "лавровых листа", 2, .piece),
        line("10 шт. перепелиных яиц", "перепелиных яиц", 10, .piece),
        line("3 ст. л. сметаны, 20%", "сметаны", 3, .tablespoon, note: "20%"),
        line("Два яйца", "яйца", 2, .piece),
        line("Полстакана молока", "молока", 0.5, .cup),
        line("Пол литра кефира", "кефира", 0.5, .liter),
        line("Пол-лимона", "лимона", 0.5, .piece),
        line("Сок половины лимона", "Сок лимона", 0.5, .piece),
        // Notes in brackets, sizes and purposes.
        line("200 г сливочного масла (растопить)", "сливочного масла", 200, .gram, note: "растопить"),
        line("1 банка консервированного тунца (185 г)", "консервированного тунца", 1, .can, note: "185 г"),
        line("Лук репчатый — 1 шт. (крупный)", "Лук репчатый", 1, .piece, note: "крупный"),
        line("1 средняя луковица", "луковица", 1, .piece, note: "средняя"),
        line("2 крупных помидора", "помидора", 2, .piece, note: "крупных"),
        line("Ванильный сахар — 1 пакетик (10 г)", "Ванильный сахар", 1, .pack, note: "10 г"),
        line("Кефир — 1 стакан (250 мл)", "Кефир", 1, .cup, note: "250 мл"),
        line("Кокосовое молоко — 1 банка (400 мл)", "Кокосовое молоко", 1, .can, note: "400 мл"),
        line("Сыр твёрдый — 100 г (например, гауда)", "Сыр твёрдый", 100, .gram, note: "например, гауда"),
        line("Масло растительное для жарки", "Масло растительное", note: "для жарки"),
        line("Зелень для подачи", "Зелень", note: "для подачи"),
        line("Мускатный орех — на кончике ножа", "Мускатный орех", note: "на кончике ножа"),
        line("Изюм 50 г (по желанию)", "Изюм", 50, .gram, note: "по желанию", optional: true),
        line("Корица — по желанию", "Корица", note: "по желанию", optional: true),
        // A unit without a number.
        line("Петрушка — пучок", "Петрушка", 1, .bunch),
        line("Пучок укропа", "укропа", 1, .bunch),
        line("Щепотка соли", "соли", 1, .pinch),
        line("Перец чёрный молотый — щепотка", "Перец чёрный молотый", 1, .pinch),
        line("Листья салата — пучок", "Листья салата", 1, .bunch),
        line("Стакан молока", "молока", 1, .cup),
        // To taste.
        line("Соль — по вкусу", "Соль", nil, .toTaste),
        line("Соль (по вкусу)", "Соль", nil, .toTaste),
        several("Соль, перец — по вкусу", ["Соль", "перец"], unit: .toTaste),
        several("соль и перец по вкусу", ["соль", "перец"], unit: .toTaste),
        // List markers.
        line("• Морковь — 2 шт.", "Морковь", 2, .piece),
        line("1. Мука — 200 г", "Мука", 200, .gram),
    ]

    @Test(arguments: cases)
    func readsTheLine(_ test: Case) {
        #expect(IngredientParser.parse(test.line) == test.expected)
    }

    @Test func thereAreEnoughRealLines() {
        #expect(Self.cases.count >= 50)
    }

    @Test func aLineWithoutAProductGivesNothing() {
        #expect(IngredientParser.parse("по вкусу").isEmpty)
        #expect(IngredientParser.parse("   ").isEmpty)
        #expect(IngredientParser.parse("200 г").isEmpty)
    }
}
