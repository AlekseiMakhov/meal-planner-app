# Meal Planner & Recipes

Приложение для Mac: рецепты с КБЖУ, база продуктов, запасы дома, список покупок и меню на неделю. Claude Desktop и Claude Code работают с ним через MCP. Список покупок попадает на iPhone через «Напоминания».

План и решения — [plan-meal-planner.md](plan-meal-planner.md). Сейчас готовы этапы 0 и 1:
- каркас проекта, тёмное окно с разделами, база данных и MCP-сервер с инструментом `get_status`;
- база продуктов: 354 продукта с КБЖУ из USDA FoodData Central и с типичных упаковок, единицы и пересчёты, разбор строк ингредиентов;
- экран «Продукты»: поиск без учёта «ё» и окончаний, фильтры, сортировка по колонкам, подгрузка при прокрутке, правка в инспекторе, объединение дублей.

Значения КБЖУ с пометкой USDA взяты из USDA FoodData Central, SR Legacy (общественное достояние).

## Что нужно

- macOS 26 и Xcode 26.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
- Для `make mcp-inspect` — Node.js 22.19 или новее (`npx`).

## Как запустить

```bash
make run
```

Проект Xcode генерируется из `project.yml` и в git не хранится. Остальные команды — в [CLAUDE.md](CLAUDE.md).

## Подключить к Claude вручную

На этапе 3 появится кнопка в Настройках. До тех пор сервер подключается руками. Сначала установите приложение, чтобы у сервера был постоянный путь:

```bash
make install
```

Claude Desktop — добавить в `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "meal-planner": {
      "command": "/Applications/MealPlanner.app/Contents/Helpers/meal-planner-mcp"
    }
  }
}
```

Claude Code:

```bash
claude mcp add meal-planner -- /Applications/MealPlanner.app/Contents/Helpers/meal-planner-mcp
```
