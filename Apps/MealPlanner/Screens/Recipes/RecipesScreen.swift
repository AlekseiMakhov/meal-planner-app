import MealCore
import MealStore
import SwiftUI

/// A recipe page to open, in edit mode right away for a new recipe.
struct RecipeRoute: Hashable {
    let id: Recipe.ID
    var startsEditing = false
}

/// The recipes: a gallery grouped by category, as in Notion, or a table of nutrition; search, filters and
/// order are shared by both. A recipe opens as a page on top.
struct RecipesScreen: View {
    enum Mode: String {
        case gallery, table
    }

    let database: AppDatabase
    /// The category chosen in the sidebar: the list starts filtered by it.
    let categoryID: RecipeCategory.ID?

    @Environment(AppModel.self) private var model
    @AppStorage("recipes.mode") private var mode = Mode.gallery
    @State private var query: RecipeQuery
    @State private var collapsed: Set<RecipeCategory.ID?> = []
    @State private var gallery: PagedList<RecipeGalleryQuery, GalleryItem>
    @State private var table: PagedList<RecipeQuery, RecipeCard>
    @State private var groups: [RecipeGroup] = []
    @State private var categories: [RecipeCategory] = []
    @State private var mealTypes: [MealType] = []
    @State private var path: [RecipeRoute] = []
    @State private var searchText = ""
    @State private var sortOrder = [RecipeOrder(.title)]
    @State private var showsTrash = false
    @State private var importsWithClaude = false
    @State private var problem: String?

    init(database: AppDatabase, categoryID: RecipeCategory.ID?) {
        self.database = database
        self.categoryID = categoryID
        let query = RecipeQuery(categoryIDs: categoryID.map { [$0] } ?? [])
        _query = State(initialValue: query)
        _gallery = State(
            initialValue: PagedList(query: RecipeGalleryQuery(recipes: query)) { query, limit in
                database.observeRecipeGallery(query, limit: limit)
            })
        _table = State(
            initialValue: PagedList(query: query) { query, limit in
                database.observeRecipeCards(query, limit: limit)
            })
    }

    var body: some View {
        NavigationStack(path: $path) {
            list
                .navigationDestination(for: RecipeRoute.self) { route in
                    RecipePage(database: database, route: route, categories: categories, mealTypes: mealTypes) {
                        path.removeAll { $0.id == route.id }
                    }
                }
        }
        .task {
            gallery.start()
            table.start()
            mealTypes = (try? database.mealTypes()) ?? []
            do {
                for try await summaries in database.observeCategories() { categories = summaries.map(\.category) }
            } catch {
                problem = String(describing: error)
            }
        }
        .task(id: query) {
            do {
                for try await groups in database.observeRecipeGroups(query) { self.groups = groups }
            } catch {
                problem = String(describing: error)
            }
        }
        .onChange(of: query) {
            gallery.query.recipes = query
            table.query = query
        }
        .onChange(of: collapsed) { gallery.query.collapsed = collapsed }
        .onChange(of: sortOrder) { query.sort = sortOrder.map(\.term) }
        .onChange(of: categoryID) {
            query.categoryIDs = categoryID.map { [$0] } ?? []
            path = []
        }
        .onDisappear {
            gallery.stop()
            table.stop()
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            RecipeFilterBar(database: database, query: $query, categories: categories, mealTypes: mealTypes)
            Divider()
            Group {
                switch mode {
                case .gallery:
                    RecipeGallery(
                        list: gallery, groups: groups, categories: categories, collapsed: $collapsed,
                        images: database.images, open: open)
                case .table:
                    RecipeTable(list: table, categories: categories, sortOrder: $sortOrder, open: open)
                }
            }
            .overlay { emptyState }
            Divider()
            // The gallery repeats a recipe in each of its categories; the table counts each recipe once.
            ListFooter(
                shown: mode == .table ? table.rows.count : table.total, total: table.total,
                noun: ("рецепт", "рецепта", "рецептов"))
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Название, продукт или шаг")
        .task(id: searchText) {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            query.text = searchText
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Вид", selection: $mode) {
                    Label("Галерея", systemImage: "square.grid.2x2").tag(Mode.gallery)
                    Label("Таблица КБЖУ", systemImage: "tablecells").tag(Mode.table)
                }
                .pickerStyle(.segmented)
                sortMenu
                Button("Новый рецепт", systemImage: "plus", action: addRecipe)
                Menu("Ещё", systemImage: "ellipsis.circle") {
                    Button("Импорт по ссылке с Claude…", systemImage: "sparkles") { importsWithClaude = true }
                    Button("Перенести из Notion с Claude") {
                        model.askClaude(ClaudeRequest.migrateFromNotion("Recipes"))
                    }
                    Divider()
                    Button("Корзина…") { showsTrash = true }
                }
            }
        }
        .sheet(isPresented: $showsTrash) { TrashSheet(database: database) }
        .sheet(isPresented: $importsWithClaude) {
            ClaudeImportSheet(categories: categories, categoryID: categoryID) { request in
                model.askClaude(request)
            }
        }
        .alert("Не получилось", isPresented: isPresent($problem), presenting: problem) { _ in
            Button("Понятно") {}
        } message: { problem in
            Text(problem)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if table.isLoaded, table.total == 0 {
            if query.text.isEmpty, query.filterCount == 0 {
                ContentUnavailableView {
                    Label("Рецептов пока нет", systemImage: "book.closed")
                } description: {
                    Text("Заведите первый рецепт или попросите Claude перенести их из Notion.")
                } actions: {
                    Button("Новый рецепт", action: addRecipe)
                }
            } else {
                ContentUnavailableView {
                    Label("Ничего не нашлось", systemImage: "magnifyingglass")
                } description: {
                    Text("Попробуйте другой запрос или сбросьте фильтры.")
                } actions: {
                    if query.filterCount > 0 {
                        Button("Сбросить фильтры") { query = query.withoutFilters }
                    }
                }
            }
        } else if let failure = table.failure ?? gallery.failure {
            ContentUnavailableView(
                "Список не загрузился", systemImage: "exclamationmark.triangle", description: Text(failure))
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Сортировать по", selection: sortKey) {
                ForEach(RecipeQuery.SortKey.allCases, id: \.self) { key in
                    if key != .relevance || !searchText.isEmpty {
                        Text(key.title).tag(key)
                    }
                }
            }
            .pickerStyle(.inline)
            Picker("Порядок", selection: sortDirection) {
                Text("По возрастанию").tag(SortOrder.forward)
                Text("По убыванию").tag(SortOrder.reverse)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Сортировка", systemImage: "arrow.up.arrow.down")
        }
    }

    private var sortKey: Binding<RecipeQuery.SortKey> {
        Binding {
            sortOrder.first?.key ?? .title
        } set: { key in
            sortOrder = [RecipeOrder(key, order: sortOrder.first?.order ?? .forward)]
        }
    }

    private var sortDirection: Binding<SortOrder> {
        Binding {
            sortOrder.first?.order ?? .forward
        } set: { order in
            sortOrder = [RecipeOrder(sortOrder.first?.key ?? .title, order: order)]
        }
    }

    private func open(_ id: Recipe.ID) {
        path.append(RecipeRoute(id: id))
    }

    /// A new recipe in the category the list shows, opened for editing.
    private func addRecipe() {
        do {
            let details = try database.newRecipe(in: query.categoryIDs.count == 1 ? Array(query.categoryIDs) : [])
            path.append(RecipeRoute(id: details.recipe.id, startsEditing: true))
        } catch {
            problem = String(describing: error)
        }
    }
}

extension RecipeQuery.SortKey {
    var title: String {
        switch self {
        case .title: "Название"
        case .kcalPer100: "Калорийность на 100 г"
        case .kcalPerServing: "Калорийность порции"
        case .protein: "Белки в порции"
        case .fat: "Жиры в порции"
        case .carbs: "Углеводы в порции"
        case .totalTime: "Время"
        case .createdAt: "Дата добавления"
        case .updatedAt: "Дата изменения"
        case .availability: "Наличие продуктов"
        case .lastCooked: "Давно не готовили"
        case .relevance: "Совпадение с поиском"
        }
    }
}

/// A column's order for the table header; the database sorts.
struct RecipeOrder: SortComparator, Hashable {
    var key: RecipeQuery.SortKey
    var order: SortOrder

    init(_ key: RecipeQuery.SortKey, order: SortOrder = .forward) {
        self.key = key
        self.order = order
    }

    var term: SortTerm<RecipeQuery.SortKey> {
        SortTerm(key, order == .forward ? .ascending : .descending)
    }

    func compare(_ lhs: RecipeCard, _ rhs: RecipeCard) -> ComparisonResult {
        let result: ComparisonResult =
            switch key {
            case .kcalPer100: compareValues(lhs.kcalPer100, rhs.kcalPer100)
            case .kcalPerServing: compareValues(lhs.perServing?.kcal, rhs.perServing?.kcal)
            case .protein: compareValues(lhs.perServing?.protein, rhs.perServing?.protein)
            case .fat: compareValues(lhs.perServing?.fat, rhs.perServing?.fat)
            case .carbs: compareValues(lhs.perServing?.carbs, rhs.perServing?.carbs)
            case .totalTime: compareValues(lhs.totalMinutes, rhs.totalMinutes)
            case .availability: compareValues(lhs.missingCount, rhs.missingCount)
            case .lastCooked:
                compareValues(lhs.lastCookedAt ?? .distantPast, rhs.lastCookedAt ?? .distantPast)
            case .title, .createdAt, .updatedAt, .relevance:
                compareValues(SearchText.normalized(lhs.title), SearchText.normalized(rhs.title))
            }
        guard order == .reverse else { return result }
        return switch result {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }

    private func compareValues<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (let lhs?, let rhs?): lhs < rhs ? .orderedAscending : lhs > rhs ? .orderedDescending : .orderedSame
        case (nil, nil): .orderedSame
        case (nil, _): .orderedDescending
        case (_, nil): .orderedAscending
        }
    }
}
