import MealCore
import Testing

struct UnitTests {
    private let flour = UnitProfile(baseUnit: .gram, density: 0.528)
    private let milk = UnitProfile(baseUnit: .milliliter, density: 1.031)
    private let egg = UnitProfile(baseUnit: .piece, gramsPerPiece: 50)
    private let garlic = UnitProfile(baseUnit: .gram, gramsPerPiece: 40, namedUnits: [.clove: 5, .head: 40])

    @Test func massAndVolumeConvertWithinThemselves() {
        #expect(flour.convert(1.5, from: .kilogram, to: .gram) == 1500)
        #expect(milk.convert(2, from: .tablespoon, to: .milliliter) == 30)
        #expect(milk.convert(1, from: .cup, to: .tablespoon)! == 250.0 / 15)
        #expect(milk.convert(0.5, from: .liter, to: .cup) == 2)
    }

    @Test func volumeBecomesGramsThroughDensity() throws {
        #expect(try #require(flour.grams(1, .cup)) == 132)
        #expect(try #require(flour.inBaseUnit(2, .tablespoon)) == 15.84)
        #expect(try #require(milk.grams(200, .milliliter)) == 206.2)
    }

    @Test func piecesAndNamedUnitsGoThroughTheirWeight() throws {
        #expect(egg.grams(3, .piece) == 150)
        #expect(egg.convert(100, from: .gram, to: .piece) == 2)
        #expect(garlic.grams(3, .clove) == 15)
        #expect(garlic.convert(2, from: .head, to: .clove) == 16)
        #expect(garlic.inBaseUnit(1, .piece) == 40)
    }

    @Test func whatTheProductCannotWeighStaysUnknown() {
        #expect(flour.grams(1, .piece) == nil)
        #expect(garlic.grams(1, .bunch) == nil)
        #expect(UnitProfile(baseUnit: .gram).grams(1, .cup) == nil)
        #expect(egg.convert(1, from: .tablespoon, to: .piece) == nil)
        #expect(flour.grams(1, .pinch) == nil)
        #expect(flour.grams(1, .toTaste) == nil)
    }

    @Test func aZeroWeightDoesNotDivide() {
        let broken = UnitProfile(baseUnit: .piece, gramsPerPiece: 0)
        #expect(broken.convert(100, from: .gram, to: .piece) == nil)
    }

    @Test func wordsAgreeWithTheNumber() {
        #expect(MeasureUnit.cup.title(for: 1) == "стакан")
        #expect(MeasureUnit.cup.title(for: 2) == "стакана")
        #expect(MeasureUnit.cup.title(for: 5) == "стаканов")
        #expect(MeasureUnit.cup.title(for: 11) == "стаканов")
        #expect(MeasureUnit.cup.title(for: 21) == "стакан")
        #expect(MeasureUnit.cup.title(for: 1.5) == "стакана")
        #expect(MeasureUnit.clove.title(for: 3) == "зубчика")
        #expect(MeasureUnit.gram.title(for: 5) == "г")
        #expect(MeasureUnit.tablespoon.title(for: 2) == "ст. л.")
    }

    @Test func namedUnitsAreTheOnesAProductWeighs() {
        #expect(MeasureUnit.named.contains(.clove))
        #expect(!MeasureUnit.named.contains(.piece))
        #expect(!MeasureUnit.named.contains(.cup))
    }
}

struct NutritionTests {
    private let milk = Nutrition(kcal: 61, protein: 3.15, fat: 3.25, carbs: 4.8)
    private let egg = Nutrition(kcal: 143, protein: 12.56, fat: 9.51, carbs: 0.72)

    @Test func scalesToTheWeight() {
        #expect(milk.inGrams(200) == Nutrition(kcal: 122, protein: 6.3, fat: 6.5, carbs: 9.6))
    }

    @Test func totalCountsWhatItCould() throws {
        var total = NutritionTotal()
        total.add(egg, grams: 150)
        total.add(milk, grams: 45)
        total.add(nil, grams: 40)
        total.add(milk, grams: nil)
        #expect(total.counted == 2)
        #expect(total.ingredients == 4)
        #expect(!total.isComplete)
        #expect(total.grams == 195)
        let perServing = try #require(total.perServing(2))
        #expect(abs(perServing.kcal - (143 * 1.5 + 61 * 0.45) / 2) < 1e-9)
    }

    @Test func per100gUsesTheFinishedWeightWhenKnown() throws {
        var total = NutritionTotal()
        total.add(egg, grams: 200)
        #expect(try #require(total.per100g()).kcal == 143)
        #expect(try #require(total.per100g(finishedWeight: 100)).kcal == 286)
        #expect(NutritionTotal().per100g() == nil)
        #expect(NutritionTotal().perServing(2) == nil)
    }

    @Test func caloriesAreCheckedAgainstMacros() {
        #expect(egg.caloriesMatchMacros)
        #expect(!Nutrition(kcal: 500, protein: 10, fat: 1, carbs: 10).caloriesMatchMacros)
        #expect(Nutrition(kcal: 15, protein: 0.65, fat: 0.11, carbs: 3.63).caloriesMatchMacros)
    }
}
