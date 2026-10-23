import Foundation
import Testing

@testable import MealCore

struct RecipeImportTests {
    /// The shape WordPress recipe plugins write: a @graph with the page, the article and the recipe.
    private let wordpress = """
        <html><head>
        <script type="application/ld+json" class="yoast-schema-graph">{"@context":"https://schema.org","@graph":[
          {"@type":"WebPage","name":"Омлет"},
          {"@type":"Recipe","name":"Омлет с&nbsp;помидорами и&nbsp;фетой","description":"<p>Завтрак за 10 минут</p>",
           "image":["https://example.com/omelette-1200.jpg","https://example.com/omelette-600.jpg"],
           "recipeYield":["2","2 порции"],"prepTime":"PT5M","cookTime":"PT10M","totalTime":"PT15M",
           "recipeIngredient":["3 яйца","3 ст. л. молока","40 г феты","Соль &amp; перец по вкусу"],
           "recipeInstructions":[
             {"@type":"HowToSection","name":"Омлет","itemListElement":[
               {"@type":"HowToStep","text":"Взбить яйца с молоком."},
               {"@type":"HowToStep","text":"Обжарить помидоры, залить яйцом."}]},
             {"@type":"HowToStep","text":"Посыпать фетой &#8212; и под крышку."}],
           "video":{"@type":"VideoObject","embedUrl":"https://www.youtube.com/embed/OSHycXV4Quo"}}
        ]}</script>
        </head><body>…</body></html>
        """

    @Test func aRecipeInAGraphComesOutWhole() throws {
        let recipe = try #require(
            RecipeImport.recipe(inHTML: wordpress, url: URL(string: "https://example.com/omlet/")))
        #expect(recipe.title == "Омлет с помидорами и фетой")
        #expect(recipe.description == "Завтрак за 10 минут")
        #expect(recipe.imageURL?.absoluteString == "https://example.com/omelette-1200.jpg")
        #expect(recipe.servings == 2)
        #expect(recipe.prepMinutes == 5)
        #expect(recipe.cookMinutes == 10)
        #expect(recipe.totalMinutes == 15)
        #expect(recipe.ingredients == ["3 яйца", "3 ст. л. молока", "40 г феты", "Соль & перец по вкусу"])
        #expect(
            recipe.steps == [
                "Взбить яйца с молоком.", "Обжарить помидоры, залить яйцом.", "Посыпать фетой — и под крышку.",
            ])
        #expect(recipe.videoURL == "https://www.youtube.com/embed/OSHycXV4Quo")
        #expect(recipe.sourceURL == "https://example.com/omlet/")
    }

    @Test func plainRecipesArraysAndOddFieldsAreReadToo() throws {
        let html = """
            <script type='application/ld+json'>[{"@type":["Recipe","NewsArticle"],"name":"Борщ",
            "image":{"@type":"ImageObject","url":"/img/borsch.jpg"},"recipeYield":"Serves 6","totalTime":"P0DT1H30M",
            "recipeIngredient":["500 г говядины","1 свёкла"],"recipeInstructions":"Сварить бульон.\\nДобавить свёклу."}]
            </script>
            """
        let recipe = try #require(RecipeImport.recipe(inHTML: html, url: URL(string: "https://food.example/borsch")))
        #expect(recipe.title == "Борщ")
        #expect(recipe.imageURL?.absoluteString == "https://food.example/img/borsch.jpg")
        #expect(recipe.servings == 6)
        #expect(recipe.totalMinutes == 90)
        #expect(recipe.steps == ["Сварить бульон.", "Добавить свёклу."])
    }

    @Test func aPageWithoutARecipeHasNone() {
        #expect(RecipeImport.recipe(inHTML: "<html><body>Омлет</body></html>") == nil)
        #expect(
            RecipeImport.recipe(inHTML: #"<script type="application/ld+json">{"@type":"Article","name":"x"}</script>"#)
                == nil)
        #expect(RecipeImport.recipe(inHTML: #"<script type="application/ld+json">{ broken</script>"#) == nil)
    }

    @Test func durationsAndYieldsTakeTheirUsualShapes() {
        #expect(RecipeImport.minutes("PT1H30M") == 90)
        #expect(RecipeImport.minutes("PT45M") == 45)
        #expect(RecipeImport.minutes("PT30S") == 1)
        #expect(RecipeImport.minutes("P1D") == 1440)
        #expect(RecipeImport.minutes("PT0M") == nil)
        #expect(RecipeImport.minutes("30 минут") == nil)
        #expect(RecipeImport.servings(4) == 4)
        #expect(RecipeImport.servings("4–6 порций") == 4)
        #expect(RecipeImport.servings("много") == nil)
        #expect(RecipeImport.clean("Соль<br>перец &#x2014; по вкусу") == "Соль\nперец — по вкусу")
    }
}
