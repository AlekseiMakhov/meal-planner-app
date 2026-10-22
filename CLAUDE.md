# CLAUDE.md

## Что это

Meal Planner & Recipes — macOS-приложение: рецепты с КБЖУ, база продуктов, запасы дома, список покупок и меню на неделю. Данные доступны Claude Desktop и Claude Code через MCP. Сейчас готов этап 0 — каркас.

- Замысел, решения и этапы — [plan-meal-planner.md](plan-meal-planner.md). Решения оттуда не пересматриваем без явной просьбы; новое решение сначала вносим в план.

## Команды

| Команда | Что делает |
|---|---|
| `make project` | Генерирует `MealPlanner.xcodeproj` из `project.yml` (XcodeGen) |
| `make build` | Debug-сборка приложения и MCP-утилиты (по умолчанию для `make`) |
| `make test` | `swift test` для пакета, затем тесты приложения через `xcodebuild` |
| `make test-package` | Только тесты `MealKit`: быстро, без Xcode-проекта |
| `make run` | Собрать и запустить Debug-версию |
| `make install` | Release-сборка в `/Applications` — нужна для постоянного пути MCP-сервера |
| `make mcp-inspect` | MCP Inspector для встроенного `meal-planner-mcp` |
| `make format` / `make lint` | `swift-format` из тулчейна, настройки — в `.swift-format` |
| `make clean` | Удалить `build/` и `.build/` пакета |

`.xcodeproj` не хранится в git. После правки `project.yml`, добавления или удаления файлов — `make project`. Настройки сборки меняем только в `project.yml`: правки в интерфейсе Xcode сотрёт следующая генерация. Сборки из терминала лежат в `build/DerivedData`.

## Структура и границы модулей

- `Apps/MealPlanner` — SwiftUI-приложение: окно, экраны, связь с macOS. Здесь только интерфейс, логика — в пакете. Папки: `App` (точка входа, `AppModel`), `Window`, `Screens`, `Settings`, `Resources` (`Assets.xcassets` с цветовыми токенами, `Localizable.xcstrings`).
- `Apps/MCPServer` — точка входа `meal-planner-mcp`; утилита встраивается в `MealPlanner.app/Contents/Helpers/`.
- `Apps/MealPlannerTests` — тесты, которым нужен собранный бандл приложения.
- `Packages/MealKit` — вся логика:
  - `MealCore` — модели и логика: единицы, КБЖУ, наличие, запросы для списков; а также имена, общие для всех частей (`AppIdentity`). Только Foundation: без AppKit, SwiftUI и GRDB.
  - `MealStore` → `MealCore`, GRDB: схема, миграции, репозитории.
  - `MealMCP` → `MealCore`, `MealStore`, MCP SDK: инструменты для Claude.
  - `MealReminders` (EventKit) появится на этапе 6.

## Подпись и идентификаторы

- Команда `6S43T3N4UL` — та же, что у Portion и Market Monitor; подпись автоматическая. `xcodebuild` запускается с `-allowProvisioningUpdates` (уже в Makefile).
- Название для людей — «Meal Planner & Recipes» (`AppIdentity.displayName`, `CFBundleDisplayName`). Цели сборки, бандл и файлы называются `MealPlanner` — без «&» и пробелов.
- Bundle ID: приложение `inco.mealplanner.app` (Debug — `inco.mealplanner.app.debug`), MCP-утилита `inco.mealplanner.mcp`, тесты `inco.mealplanner.app.tests`. URL-схема `mealplanner` (Debug — `mealplanner-debug`).
- Песочница выключена, Hardened Runtime включён. Минимальная macOS — 26.0.

## Правила кода

- Swift 6 со строгой проверкой конкурентности: модели `Sendable`, интерфейс — `@MainActor`.
- Тесты — Swift Testing (`import Testing`). Код ядра попадает в коммит только вместе с тестами.
- Компилятор и `make lint` — без предупреждений.
- Тексты интерфейса — по-русски; комментарии в коде — по-английски.
- Логи — `os.Logger` с subsystem `inco.mealplanner`.
- MCP-сервер пишет в stdout только протокол; диагностика — в stderr или `os.Logger`.

## Интерфейс и тема

- Тема тёмная: `AppDelegate` ставит `NSApp.appearance = .darkAqua` до первого кадра, поэтому тёмные и окна, и меню, и алерты, и Настройки.
- Цвета — только токены из `Assets.xcassets` через сгенерированные символы: `Color(.canvas)`, `Color(.textSecondary)`… Цветовых литералов в коде нет. Пока у каждого токена одно значение — тёмное; светлая тема добавит к тем же токенам светлый вариант.
- Токены: `Canvas` (фон окна), `Surface`, `SurfaceRaised`, `Card`, `Hairline`, `TextPrimary`, `TextSecondary`, `StatusInStock` / `StatusLow` / `StatusMissing`, `MealBreakfast` / `MealLunch` / `MealDinner` / `MealSnack`, `AccentColor`.

## Хранилище и данные

- База — `AppDatabase` (GRDB): `~/Library/Application Support/inco.mealplanner/meals.sqlite`, у Debug — папка `inco.mealplanner.debug`. И приложение, и MCP-сервер пишут через `DatabasePool` (WAL) с ожиданием блокировки до 5 секунд.
- Схема меняется только новой миграцией в `AppDatabase.migrator`; уже применённые миграции не редактируем. Первые таблицы появятся на этапе 1.

## MCP

- Сервер `meal-planner` (`MealMCPServer`), транспорт stdio. Без аргументов внутри бандла работает с данными своего приложения (Debug — со своими); `--directory <папка>` — с указанной.
- Пока есть один инструмент — `get_status`, и он не создаёт базу, если её ещё нет.
- Новый инструмент: определение в `MealTools.all`, ветка в `MealTools.call`, тесты в `MealMCPTests`. `PackagingTests` проверяет, что встроенный в бандл сервер отвечает по stdio.
- До этапа 3 сервер подключается к Claude вручную — см. README.
