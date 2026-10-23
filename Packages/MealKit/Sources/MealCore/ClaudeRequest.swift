/// What the app and the MCP server ask Claude to do, step by step with the server's tools: the MCP prompts and
/// the app's «… с Claude» buttons send the same words.
public enum ClaudeRequest {
    /// The conventions the data follows: told to Claude when it connects and written into the Claude folder.
    public static let rules = """
        - Продукт называется в именительном падеже, с большой буквы, как в магазине: «Сыр фета», «Молоко 3,2%». Прежде \
        чем создавать продукт, поищи его через search_products; дубли объединяет merge_products.
        - КБЖУ продукта — на 100 г съедобной части. КБЖУ рецепта считается из ингредиентов: на 100 г и на порцию.
        - Количество ингредиента — amount и unit (g, ml, pcs, tbsp, clove…); без amount — «по вкусу». Порций по умолчанию — 2: \
        едят двое.
        - Запасы — в основной единице продукта (g, ml, pcs); quantity null — «есть, без счёта», 0 — закончилось. \
        Купленное — в запасы через check_shopping_items со stock или adjust_pantry.
        - Удалённый рецепт 30 дней лежит в корзине приложения.
        - Длинные списки читай частями: limit и cursor из next_cursor.
        - Меню — по дням («2026-10-23») и приёмам пищи; КБЖУ дня на человека — порция каждого блюда. «Приготовлено» \
        (mark_cooked) списывает запасы только после моего согласия: сначала покажи, что спишется.
        - Готовые сценарии — промпты import_recipe, fill_recipe, fill_nutrition, what_to_cook, plan_week и \
        migrate_from_notion.
        """

    /// How products and their nutrition are filled: shared by the prompts that create products.
    public static let nutritionRules = """
        КБЖУ продукта — на 100 г съедобной части, все четыре значения сразу, через upsert_product. Источники по порядку: \
        USDA FoodData Central (source: usda, в source_note — номер FDC и название записи), упаковка типичного продукта из \
        российского магазина (label), справочник (reference). Калории сверяй с 4·Б + 9·Ж + 4·У: расхождение больше 15 % — \
        повод перепроверить. Приблизительные значения помечай needs_review: true. Задай пересчёты: grams_per_piece для \
        штучного (яйцо, луковица), density для того, что меряют ложками и стаканами, units для зубчика, пучка, ломтика.
        """

    public static func importRecipe(url: String, category: String?) -> String {
        """
        Добавь в Meal Planner рецепт по ссылке: \(url)

        1. Открой страницу и найди сам рецепт: название, порции, ингредиенты с количеством, шаги, время, фото блюда, видео. \
        Если у страницы есть разметка schema.org/Recipe (JSON-LD), бери данные из неё. Если это видео — возьми рецепт из \
        описания, а чего там нет, спроси у меня.
        2. Проверь через search_recipes, нет ли такого рецепта уже.
        3. Ингредиенты передавай объектами: name — продукт в именительном падеже, как он называется в магазине \
        («Сыр фета», «Яйцо куриное»), amount, unit, note. Чтобы не плодить дубли, сначала поищи продукты через search_products.
        4. Вызови create_recipe: title, servings (как в источнике; не указано — 2), ingredients, steps (без номеров), \
        source_url, image_url (фото готового блюда, не логотип), video_url, prep_minutes и cook_minutes\
        \(category.map { ", categories: [«\($0)»]" } ?? ", categories — подходящие из list_categories"), meal_types. \
        Если источник даёт КБЖУ на 100 г — nutrition_per_100g.
        5. Продукты из created_products заполни: \(nutritionRules)
        6. Проверь matched_by_search: если продукт подобран неверно, исправь строку через update_recipe.
        7. В конце коротко: что добавлено, КБЖУ на порцию и какие продукты созданы.
        """
    }

    /// `recipe` as the request names it: «Омлет» (id 12).
    public static func fillRecipe(_ recipe: String) -> String {
        """
        Дозаполни рецепт \(recipe) в Meal Planner.

        1. Найди его: get_recipe по id или search_recipes по названию.
        2. Посмотри nutrition.missing и nutrition.complete: у каких продуктов нет КБЖУ или пересчёта в граммы. \
        \(nutritionRules)
        3. Если не хватает времени, порций, шагов, категорий, приёмов пищи или фото — предложи значения и, когда я \
        соглашусь, сохрани через update_recipe. Количества ингредиентов без меня не меняй.
        4. В конце — КБЖУ на 100 г и на порцию после правок.
        """
    }

    public static func fillNutrition(_ products: String?) -> String {
        let which =
            products.map { "Продукты: \($0). Найди каждый через search_products." }
            ?? "Возьми все продукты с nutrition: \"missing\" через search_products — читай все страницы через cursor."
        return """
            Заполни КБЖУ продуктов в Meal Planner.

            1. \(which)
            2. \(nutritionRules)
            3. Работай партиями по 10–20 продуктов и не спрашивай подтверждения для каждого.
            4. В конце — таблица: продукт, ккал, Б, Ж, У, источник; отдельно — что пометил «проверить» и почему.
            """
    }

    /// «Что приготовить сегодня»: from what there is at home, for `meal` if given.
    public static func whatToCook(meal: String?, wishes: String?) -> String {
        let when = meal.map { "на \($0.lowercased())" } ?? "сегодня"
        let wished = wishes.map { " Пожелания: \($0)." } ?? ""
        let meals = meal.map { " и meal_types [«\($0)»]" } ?? ""
        return """
            Подскажи, что приготовить \(when) из того, что есть дома, по Meal Planner.\(wished)

            1. Найди рецепты, для которых всё есть: search_recipes с max_missing 0\(meals), sort availability. Если \
            таких меньше трёх — добавь те, где не хватает одного-двух ингредиентов (max_missing 2).
            2. Проверь в get_recipe, чего именно не хватает (at_home и need_more), и посмотри get_pantry: что \
            заканчивается (status low) — то лучше пустить в дело.
            3. Предложи три варианта: название, КБЖУ на порцию, время и чего не хватает. Коротко, без пересказа рецепта.
            4. Когда я выберу, предложи добавить недостающее в покупки: add_to_shopping_list с recipe.
            """
    }

    /// «Меню на неделю из того, что есть».
    public static func planWeek(week: String?, wishes: String?) -> String {
        let which = week.map { "на неделю с днём \($0)" } ?? "на эту неделю"
        let wished = wishes.map { " Пожелания: \($0)." } ?? ""
        return """
            Составь в Meal Planner меню \(which) из того, что есть дома.\(wished)

            1. Посмотри get_week_plan: что уже запланировано, — и get_pantry: что есть, что заканчивается (status low).
            2. Подбери рецепты через search_recipes: сначала те, для чего всё есть (max_missing 0, sort availability), и \
            те, что давно не готовили (sort last_cooked). Разнообразь: не повторяй блюдо чаще двух раз за неделю, чередуй \
            продукты; на человека выходи примерно на 1800–2200 ккал в день, если я не попросил иначе.
            3. Предложи меню таблицей: дни × завтрак, обед, ужин, перекус — и КБЖУ за день. Порции — 2, едим вдвоём.
            4. Когда я соглашусь, поставь блюда через plan_meal, затем положи недостающее в покупки: \
            add_to_shopping_list с week. В конце — что добавлено в меню и в покупки.
            """
    }

    /// The move from Notion. `database` defaults to the Food base on the Recipes page, whose layout the request
    /// describes; another base is read the same way, by what its pages hold.
    public static func migrateFromNotion(_ database: String) -> String {
        """
        Перенеси рецепты из Notion в Meal Planner. База в Notion: \(database).

        Как устроена база Food на странице Recipes (другую базу читай так же, по смыслу полей):
        - Category: Recipe — рецепт, Single food — отдельный продукт с КБЖУ с упаковки.
        - Meal type — категория рецепта («Завтраки», «Гарнир», «Ужины»…), Meal time — приём пищи (завтрак, обед, ужин).
        - Calories, Protein, Fat, Carbs — КБЖУ на 100 г, Serving size — граммов в порции.
        - На странице рецепта: обложка — фото блюда; в блоке «Ингредиенты на N порции» — встроенная база Ingredients \
        (Name, Quantity, Unit, Type: Sauce — строка соуса); под «Способ приготовления» — шаги; закладка-ссылка — видео \
        или источник.

        1. Сначала вызови list_categories и search_recipes: рецепт с таким же названием уже есть — не создавай его \
        повторно, а упомяни в отчёте.
        2. Читай рецепты по одному: страницу, затем её базу ингредиентов, и сразу создавай рецепт через create_recipe — \
        ссылка на обложку живёт несколько минут, поэтому передай её в image_url без промедления.
        3. Поля: title — Name; servings — N из «Ингредиенты на N порции», иначе 2; categories — [Meal type]; meal_types \
        — Meal time; steps — шаги без номеров; video_url — ссылка на YouTube, Rutube или VK, другая ссылка — source_url. \
        Если Calories, Protein, Fat и Carbs заполнены — nutrition_per_100g с ними и yield_grams = Serving size × servings, \
        когда Serving size есть.
        4. Ингредиенты — объектами: name — продукт в именительном падеже («Яйца» → «Яйцо куриное», если такой есть в \
        search_products), amount — Quantity, unit — Unit как есть («гр.», «шт.», «ст. л.», «пуч.», «зб.»); строки с Type \
        Sauce, если это и правда соус или заправка, — group «Для соуса». Без Quantity — без amount: это «по вкусу». Если \
        ингредиенты не читаются (связанная база недоступна), создай рецепт без них — с шагами, фото и КБЖУ из свойств — и \
        назови его в отчёте: ингредиенты можно дописать в приложении.
        5. Строки Single food — продукты: найди такой через search_products; нет — создай через upsert_product с \
        названием без вертикальных черт и бренда («Кетчуп | -50% | Heinz» → «Кетчуп», бренд и вариант — в source_note) \
        и КБЖУ с source: label. Если продукт есть, но у него нет КБЖУ, заполни его этими значениями.
        6. Когда рецепты перенесены, заполни продукты из created_products: \(nutritionRules) Работай партиями.
        7. Если рядом есть база запасов Pantry (Name, Status, Section, Store) — перенеси и её: In stock — set_pantry без \
        quantity; Running low — set_pantry с low: true; To buy — add_to_shopping_list; Don't need — пропусти. Продукт \
        ищи через search_products, а если его нет — создай через upsert_product с подходящим отделом.
        8. Отчёт: сколько рецептов перенесено, что пропущено и почему, где не скачалось фото, сколько продуктов создано и \
        заполнено, что попало в запасы и в покупки.
        """
    }
}
