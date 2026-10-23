import Foundation
import MealCore
import Testing

struct RecipeTests {
    /// The omelette from the Notion base, with the starting base's values for its products.
    private let egg = Product(
        id: 1, name: "Яйцо куриное", kcal: 143, protein: 12.56, fat: 9.51, carbs: 0.72, baseUnit: .piece,
        gramsPerPiece: 50)
    private let milk = Product(
        id: 2, name: "Молоко 3,2%", kcal: 61, protein: 3.15, fat: 3.25, carbs: 4.8, baseUnit: .milliliter,
        density: 1.031)
    private let cherry = Product(
        id: 3, name: "Помидоры черри", kcal: 18, protein: 0.88, fat: 0.2, carbs: 3.89, gramsPerPiece: 17)
    private let feta = Product(id: 4, name: "Фета", kcal: 265, protein: 14.21, fat: 21.49, carbs: 3.88)
    private let parsley = Product(id: 5, name: "Петрушка", kcal: 36, protein: 2.97, fat: 0.79, carbs: 6.33)
    private let salt = Product(id: 6, name: "Соль", kcal: 0, protein: 0, fat: 0, carbs: 0, isStaple: true)

    private var omelette: RecipeDetails {
        RecipeDetails(
            recipe: Recipe(id: 1, title: "Омлет с помидорами и фетой", servings: 2),
            ingredients: [
                RecipeIngredient(productID: 1, amount: 3, unit: .piece),
                RecipeIngredient(productID: 2, amount: 3, unit: .tablespoon),
                RecipeIngredient(productID: 3, amount: 10, unit: .piece),
                RecipeIngredient(productID: 4, amount: 40, unit: .gram),
                RecipeIngredient(productID: 5),
                RecipeIngredient(productID: 6, unit: .toTaste),
            ],
            products: Dictionary(uniqueKeysWithValues: [egg, milk, cherry, feta, parsley, salt].map { ($0.id, $0) }))
    }

    @Test func omeletteAddsUpPerServingAndPer100g() throws {
        let nutrition = omelette.nutrition
        let milkGrams = 45 * 1.031
        let kcal = 143 * 1.5 + 61 * milkGrams / 100 + 18 * 1.7 + 265 * 0.4
        let perServing = try #require(nutrition.perServing)
        #expect(abs(perServing.kcal - kcal / 2) < 1e-9)
        let per100 = try #require(nutrition.per100g)
        #expect(abs(per100.kcal - kcal / (150 + milkGrams + 170 + 40) * 100) < 1e-9)
        #expect(nutrition.isComplete, "parsley without an amount and salt to taste do not count")
        #expect(perServing.kcal > 0)
    }

    @Test func finishedWeightGivesPer100gOfTheDish() throws {
        var details = omelette
        details.recipe.yieldGrams = 350
        let total = try #require(details.nutrition.perServing).kcal * 2
        #expect(abs(try #require(details.nutrition.per100g).kcal - total / 3.5) < 1e-9)
    }

    @Test func sourceValuesReplaceTheIngredients() throws {
        var details = omelette
        details.recipe.nutritionOverride = Nutrition(kcal: 140, protein: 9, fat: 10, carbs: 3)
        details.recipe.yieldGrams = 400
        let nutrition = details.nutrition
        #expect(nutrition.isFromSource)
        #expect(nutrition.per100g?.kcal == 140)
        #expect(try #require(nutrition.perServing).kcal == 280)
    }

    @Test func ingredientsWithoutNutritionLeaveItIncomplete() {
        var details = omelette
        details.products[4]?.kcal = nil
        details.ingredients.append(RecipeIngredient(productID: 99, amount: 1, unit: .bunch))
        let nutrition = details.nutrition
        #expect(!nutrition.isComplete)
        #expect(nutrition.total.counted == 3)
        #expect(nutrition.total.ingredients == 5)
    }

    @Test func rangesCountByTheirMiddle() {
        let line = RecipeIngredient(productID: 1, amount: 2, amountMax: 4, unit: .piece)
        #expect(line.grams(of: egg) == 150)
        #expect(RecipeIngredient(productID: 1, amount: 2).grams(of: egg) == 100)
        #expect(RecipeIngredient(productID: 6, unit: .toTaste).grams(of: salt) == nil)
    }

    @Test func amountsScaleWithServings() {
        let line = RecipeIngredient(productID: 1, amount: 3, amountMax: 4, unit: .piece)
        let scaled = line.scaled(to: 3, of: 2)
        #expect(scaled.amount == 4.5)
        #expect(scaled.amountMax == 6)
        #expect(line.scaled(to: 2, of: 2) == line)
        #expect(RecipeIngredient(productID: 6, unit: .toTaste).scaled(to: 4, of: 2).amount == nil)
    }

    @Test func totalTimeAddsWhatIsKnown() {
        #expect(Recipe(id: 1, title: "А", prepMinutes: 10, cookMinutes: 15).totalMinutes == 25)
        #expect(Recipe(id: 1, title: "А", cookMinutes: 15).totalMinutes == 15)
        #expect(Recipe(id: 1, title: "А").totalMinutes == nil)
    }

    @Test func problemsExplainWhatCannotBeSaved() {
        #expect(omelette.problems.isEmpty)
        var details = omelette
        details.recipe.title = " "
        details.recipe.servings = 0
        details.recipe.yieldGrams = 0
        #expect(
            details.problems == [
                "Нужно название.", "Порций — от 1 до 100.", "Вес готового блюда должен быть больше нуля.",
            ])
    }

    @Test func queryCountsItsFilters() {
        var query = RecipeQuery(text: "омлет")
        #expect(query.filterCount == 0)
        query.kcalPerServing.max = 300
        query.categoryIDs = [1]
        query.hasPhoto = true
        #expect(query.filterCount == 3)
        #expect(query.withoutFilters == RecipeQuery(text: "омлет"))
    }
}

struct VideoEmbedTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=OSHycXV4Quo&list=PL9DtZk",
        "https://youtu.be/OSHycXV4Quo",
        "https://m.youtube.com/watch?v=OSHycXV4Quo",
        "https://www.youtube.com/shorts/OSHycXV4Quo",
        "https://www.youtube.com/embed/OSHycXV4Quo",
        #"<iframe width="560" height="315" src="https://www.youtube.com/embed/OSHycXV4Quo?si=x" allowfullscreen></iframe>"#,
    ])
    func youtubeLinksPlayInThePrivacyPlayer(_ link: String) throws {
        let player = try #require(VideoEmbed.player(for: link))
        #expect(player.provider == .youtube)
        #expect(player.url.absoluteString == "https://www.youtube-nocookie.com/embed/OSHycXV4Quo?rel=0")
        #expect(player.page.absoluteString == "https://www.youtube.com/watch?v=OSHycXV4Quo")
    }

    @Test func youtubeKeepsTheStartTime() throws {
        let player = try #require(VideoEmbed.player(for: "https://youtu.be/OSHycXV4Quo?t=1m30s"))
        #expect(player.url.absoluteString == "https://www.youtube-nocookie.com/embed/OSHycXV4Quo?rel=0&start=90")
        #expect(
            VideoEmbed.player(for: "https://www.youtube.com/watch?v=OSHycXV4Quo&t=45")?.url.query == "rel=0&start=45")
    }

    @Test func rutubeAndVK() throws {
        let rutube = try #require(VideoEmbed.player(for: "https://rutube.ru/video/0b1a4fd0e1c6a2e4b5d3c2f1e0a9b8c7/"))
        #expect(rutube.provider == .rutube)
        #expect(rutube.url.absoluteString == "https://rutube.ru/play/embed/0b1a4fd0e1c6a2e4b5d3c2f1e0a9b8c7")

        let vk = try #require(VideoEmbed.player(for: "https://vk.com/video-12345_456239017"))
        #expect(vk.provider == .vk)
        #expect(vk.url.absoluteString == "https://vkvideo.ru/video_ext.php?oid=-12345&id=456239017&hd=2")
        let clip = try #require(VideoEmbed.player(for: "https://vkvideo.ru/clip-12345_456239017"))
        #expect(clip.page.absoluteString == "https://vkvideo.ru/video-12345_456239017")
        let fromWall = try #require(
            VideoEmbed.player(for: "https://vk.com/club12345?z=video-12345_456239017%2Fvideos-12345"))
        #expect(fromWall.provider == .vk)
        let embedded = try #require(
            VideoEmbed.player(
                for:
                    #"<iframe src="https://vk.com/video_ext.php?oid=-12345&amp;id=456239017&amp;hash=abc" allow="autoplay"></iframe>"#
            ))
        #expect(embedded.url.absoluteString == "https://vkvideo.ru/video_ext.php?oid=-12345&id=456239017&hash=abc&hd=2")
    }

    @Test func anyOtherIframePlaysAsIs() throws {
        let player = try #require(
            VideoEmbed.player(for: #"<iframe src='https://player.vimeo.com/video/76979871'></iframe>"#))
        #expect(player.provider == .iframe)
        #expect(player.url.absoluteString == "https://player.vimeo.com/video/76979871")
    }

    @Test func pagesThatAreNotVideosHaveNoPlayer() {
        #expect(VideoEmbed.player(for: "https://www.russianfood.com/recipes/recipe.php?rid=123") == nil)
        #expect(VideoEmbed.player(for: "https://www.youtube.com/@channel") == nil)
        #expect(VideoEmbed.player(for: "не ссылка") == nil)
        #expect(VideoEmbed.player(for: #"<iframe src="javascript:alert(1)"></iframe>"#) == nil)
    }
}
