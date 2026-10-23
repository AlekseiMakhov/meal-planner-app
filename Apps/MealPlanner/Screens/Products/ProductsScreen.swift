import MealCore
import MealStore
import SwiftUI

/// The product base: a table with search, filters and sorting that loads in blocks as it scrolls; the
/// selected product opens in the inspector.
struct ProductsScreen: View {
    let database: AppDatabase

    @Environment(AppModel.self) private var model
    @State private var list: PagedList<ProductQuery, Product>
    @State private var aisles: [Aisle] = []
    @State private var selection: Set<Product.ID> = []
    @State private var searchText = ""
    @State private var sortOrder = [ProductOrder(.name)]
    @State private var showsInspector = false
    @State private var merging: Product?
    @State private var deleting: Product?
    @State private var problem: String?

    init(database: AppDatabase) {
        self.database = database
        _list = State(
            initialValue: PagedList(query: ProductQuery()) { query, limit in
                database.observeProducts(query, limit: limit)
            })
    }

    var body: some View {
        @Bindable var list = list
        VStack(spacing: 0) {
            ProductFilterBar(query: $list.query, aisles: aisles)
            Divider()
            table
                .overlay { emptyState }
            Divider()
            ListFooter(shown: list.rows.count, total: list.total, noun: ("продукт", "продукта", "продуктов"))
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Название или синоним")
        .toolbar {
            ToolbarItemGroup {
                sortMenu
                Button("Новый продукт", systemImage: "plus", action: addProduct)
                Button("Свойства", systemImage: "sidebar.trailing") { showsInspector.toggle() }
                Menu("Ещё", systemImage: "ellipsis.circle") {
                    Button("Заполнить КБЖУ с Claude", systemImage: "sparkles") {
                        model.askClaude(ClaudeRequest.fillNutrition(nil))
                    }
                }
            }
        }
        .inspector(isPresented: $showsInspector) {
            inspector
                .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
        }
        .task(id: searchText) {
            // A short pause, so a list is not fetched for every letter typed.
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            list.query.text = searchText
        }
        .task {
            list.start()
            do {
                for try await aisles in database.observeAisles() { self.aisles = aisles }
            } catch {
                problem = String(describing: error)
            }
        }
        .onDisappear { list.stop() }
        .onChange(of: sortOrder) { list.query.sort = sortOrder.map(\.term) }
        .onChange(of: selection) {
            if selection.count == 1 { showsInspector = true }
        }
        .sheet(item: $merging) { duplicate in
            MergeProductSheet(database: database, duplicate: duplicate) { kept in
                selection = [kept.id]
            }
        }
        .confirmationDialog(
            "Удалить «\(deleting?.name ?? "")»?", isPresented: isPresent($deleting), presenting: deleting
        ) { product in
            Button("Удалить", role: .destructive) { delete(product) }
        } message: { _ in
            Text("Продукт пропадёт из базы. Отменить это нельзя.")
        }
        .alert("Не получилось", isPresented: isPresent($problem), presenting: problem) { _ in
            Button("Понятно") {}
        } message: { problem in
            Text(problem)
        }
    }

    // MARK: - Table

    private var table: some View {
        Table(list.rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Название", sortUsing: ProductOrder(.name)) { product in
                ProductNameCell(product: product)
                    .onAppear { list.rowAppeared(product.id) }
            }
            .width(min: 180, ideal: 260)
            TableColumn("Отдел", sortUsing: ProductOrder(.aisle)) { product in
                Text(aisleName(product.aisleID))
                    .foregroundStyle(Color(.textSecondary))
            }
            .width(min: 90, ideal: 150)
            TableColumn("Ккал", sortUsing: ProductOrder(.kcal)) { product in
                NumberCell(value: product.kcal, digits: 0)
            }
            .width(52)
            TableColumn("Б", sortUsing: ProductOrder(.protein)) { product in
                NumberCell(value: product.protein)
            }
            .width(44)
            TableColumn("Ж", sortUsing: ProductOrder(.fat)) { product in
                NumberCell(value: product.fat)
            }
            .width(44)
            TableColumn("У", sortUsing: ProductOrder(.carbs)) { product in
                NumberCell(value: product.carbs)
            }
            .width(44)
            TableColumn("Ед.") { product in
                Text(product.baseUnit.unit.symbol)
                    .foregroundStyle(Color(.textSecondary))
            }
            .width(36)
            TableColumn("1 шт.") { product in
                Text(product.gramsPerPiece.map { "\(Formatting.number($0)) г" } ?? "—")
                    .foregroundStyle(Color(.textSecondary))
                    .monospacedDigit()
            }
            .width(56)
            TableColumn("Источник") { product in
                Text(product.nutritionSource?.title ?? "—")
                    .foregroundStyle(Color(.textSecondary))
            }
            .width(min: 70, ideal: 90)
        }
        .contextMenu(forSelectionType: Product.ID.self) { ids in
            let chosen = list.rows.filter { ids.contains($0.id) }
            if !chosen.isEmpty {
                Button("Заполнить КБЖУ с Claude") {
                    model.askClaude(ClaudeRequest.fillNutrition(chosen.map { "«\($0.name)»" }.joined(separator: ", ")))
                }
            }
            if ids.count == 1, let product = list.rows.first(where: { $0.id == ids.first }) {
                Button("Объединить с другим продуктом…") { merging = product }
                Divider()
                Button("Удалить…", role: .destructive) { deleting = product }
            }
        } primaryAction: { ids in
            selection = ids
            showsInspector = true
        }
    }

    @ViewBuilder private var emptyState: some View {
        if list.isLoaded, list.total == 0 {
            if list.query.text.isEmpty, list.query.filterCount == 0 {
                ContentUnavailableView {
                    Label("Продуктов пока нет", systemImage: "carrot")
                } actions: {
                    Button("Новый продукт", action: addProduct)
                }
            } else {
                ContentUnavailableView {
                    Label("Ничего не нашлось", systemImage: "magnifyingglass")
                } description: {
                    Text("Попробуйте другой запрос или сбросьте фильтры.")
                } actions: {
                    if list.query.filterCount > 0 {
                        Button("Сбросить фильтры") { list.query = list.query.withoutFilters }
                    }
                }
            }
        } else if let failure = list.failure {
            ContentUnavailableView(
                "Список не загрузился", systemImage: "exclamationmark.triangle", description: Text(failure))
        }
    }

    // MARK: - Inspector

    @ViewBuilder private var inspector: some View {
        if selection.count == 1, let id = selection.first {
            ProductEditor(database: database, productID: id, aisles: aisles) { product in
                merging = product
            } onDelete: { product in
                deleting = product
            }
            .id(id)
        } else {
            ContentUnavailableView(
                selection.isEmpty ? "Выберите продукт" : "Выбрано несколько продуктов", systemImage: "carrot",
                description: Text("Свойства, КБЖУ и единицы продукта появятся здесь."))
        }
    }

    // MARK: - Sorting

    private var sortMenu: some View {
        Menu {
            Picker("Сортировать по", selection: sortKey) {
                ForEach(ProductQuery.SortKey.allCases, id: \.self) { key in
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

    private var sortKey: Binding<ProductQuery.SortKey> {
        Binding {
            sortOrder.first?.key ?? .name
        } set: { key in
            sortOrder = [ProductOrder(key, order: sortOrder.first?.order ?? .forward)]
        }
    }

    private var sortDirection: Binding<SortOrder> {
        Binding {
            sortOrder.first?.order ?? .forward
        } set: { order in
            sortOrder = [ProductOrder(sortOrder.first?.key ?? .name, order: order)]
        }
    }

    // MARK: - Actions

    private func addProduct() {
        do {
            let product = try database.newProduct()
            selection = [product.id]
            showsInspector = true
        } catch {
            problem = String(describing: error)
        }
    }

    private func delete(_ product: Product) {
        do {
            try database.deleteProduct(id: product.id)
            selection.remove(product.id)
        } catch {
            problem = String(describing: error)
        }
    }

    private func aisleName(_ id: Int64?) -> String {
        aisles.first { $0.id == id }?.name ?? "—"
    }
}

extension ProductQuery.SortKey {
    var title: String {
        switch self {
        case .name: "Название"
        case .aisle: "Отдел"
        case .kcal: "Калорийность"
        case .protein: "Белки"
        case .fat: "Жиры"
        case .carbs: "Углеводы"
        case .createdAt: "Дата добавления"
        case .recipeCount: "Число рецептов"
        case .relevance: "Совпадение с поиском"
        }
    }
}

/// A column's order for the table header. The database sorts; the table only shows which column it is.
struct ProductOrder: SortComparator, Hashable {
    var key: ProductQuery.SortKey
    var order: SortOrder

    init(_ key: ProductQuery.SortKey, order: SortOrder = .forward) {
        self.key = key
        self.order = order
    }

    var term: SortTerm<ProductQuery.SortKey> {
        SortTerm(key, order == .forward ? .ascending : .descending)
    }

    func compare(_ lhs: Product, _ rhs: Product) -> ComparisonResult {
        let result: ComparisonResult =
            switch key {
            case .kcal: compareValues(lhs.kcal, rhs.kcal)
            case .protein: compareValues(lhs.protein, rhs.protein)
            case .fat: compareValues(lhs.fat, rhs.fat)
            case .carbs: compareValues(lhs.carbs, rhs.carbs)
            case .createdAt: compareValues(lhs.createdAt, rhs.createdAt)
            case .name, .aisle, .recipeCount, .relevance: compareValues(lhs.nameKey, rhs.nameKey)
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

private struct ProductNameCell: View {
    let product: Product

    var body: some View {
        HStack(spacing: 6) {
            Text(product.name)
                .lineLimit(1)
            if product.isStaple {
                Image(systemName: "house")
                    .foregroundStyle(Color(.textSecondary))
                    .help("Обычно есть дома")
            }
            if product.needsReview {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Нужно проверить")
            } else if product.nutrition == nil {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(Color(.textSecondary))
                    .help("КБЖУ не заполнено")
            }
        }
        .help(product.aliases.isEmpty ? "" : "Синонимы: \(product.aliases.joined(separator: ", "))")
    }
}
