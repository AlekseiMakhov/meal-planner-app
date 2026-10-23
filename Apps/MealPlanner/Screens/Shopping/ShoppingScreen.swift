import MealCore
import MealStore
import SwiftUI

/// The shopping list, by the aisles of the shop: a checkbox, how much and for which dishes. Bought items go to
/// the end; «В запасы» puts them into the pantry — after a look at the amounts, unless Settings say not to ask.
struct ShoppingScreen: View {
    let database: AppDatabase

    @AppStorage(ShoppingScreen.stocksWithoutAskingKey) private var stocksWithoutAsking = false
    @State private var list: PagedList<ShoppingQuery, ShoppingEntry>
    @State private var aisles: [Aisle] = []
    @State private var recipes: [Recipe.ID: String] = [:]
    @State private var searchText = ""
    @State private var stocking: [ShoppingEntry]?
    @State private var editing: ShoppingEntry?
    @State private var problem: String?

    /// «Пополнять запасы без вопросов»: a bought item goes into the pantry at once.
    static let stocksWithoutAskingKey = "shopping.stocksWithoutAsking"

    init(database: AppDatabase) {
        self.database = database
        _list = State(
            initialValue: PagedList(query: ShoppingQuery()) { query, limit in
                database.observeShopping(query, limit: limit)
            })
    }

    var body: some View {
        @Bindable var list = list
        VStack(spacing: 0) {
            QuickAddField(prompt: "Добавить в покупки: «молоко 1 л», «хлеб», «батарейки»", onSubmit: add)
            Divider()
            ShoppingFilterBar(query: $list.query, aisles: aisles, recipes: recipes)
            Divider()
            content
                .overlay { emptyState }
            if !boughtToStock.isEmpty, !stocksWithoutAsking {
                Divider()
                HStack {
                    Text("Куплено \(Formatting.count(boughtToStock.count, "продукт", "продукта", "продуктов"))")
                    Spacer()
                    Button("Убрать в запасы…") { stocking = boughtToStock }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.surface))
            }
            Divider()
            ListFooter(shown: list.rows.count, total: list.total, noun: ("позиция", "позиции", "позиций"))
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Что купить")
        .task(id: searchText) {
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
        .task(id: list.rows.flatMap { $0.item.reasons.compactMap(\.recipeID) }) {
            for row in list.rows {
                for reason in row.item.reasons {
                    if let id = reason.recipeID { recipes[id] = reason.title }
                }
            }
        }
        .onDisappear { list.stop() }
        .toolbar {
            ToolbarItemGroup {
                sortMenu
                ShareLink(item: shareText, subject: Text("Покупки"), preview: SharePreview("Покупки")) {
                    Label("Поделиться списком", systemImage: "square.and.arrow.up")
                }
                .disabled(list.rows.isEmpty)
                Menu("Ещё", systemImage: "ellipsis.circle") {
                    Button("Убрать купленное в запасы…") { stocking = boughtToStock }
                        .disabled(boughtToStock.isEmpty)
                    Button("Очистить купленное") { run { try database.clearChecked() } }
                        .disabled(!list.rows.contains { $0.item.isChecked })
                    Divider()
                    Toggle("Пополнять запасы без вопросов", isOn: $stocksWithoutAsking)
                }
            }
        }
        .sheet(item: Binding(get: { stocking.map(StockRequest.init) }, set: { stocking = $0?.entries })) { request in
            StockBoughtSheet(entries: request.entries) { amounts in
                run { try database.stockBought(amounts) }
            } dismissOnly: { ids in
                run { try database.removeShoppingItems(ids) }
            }
        }
        .popover(item: $editing, arrowEdge: .trailing) { entry in
            ShoppingAmountEditor(entry: entry) { amount, unit in
                run { try database.updateShoppingItem(entry.id, amount: amount, unit: unit) }
                editing = nil
            }
        }
        .alert("Не получилось", isPresented: isPresent($problem), presenting: problem) { _ in
            Button("Понятно") {}
        } message: { problem in
            Text(problem)
        }
    }

    private struct StockRequest: Identifiable {
        let entries: [ShoppingEntry]
        var id: [ShoppingItem.ID] { entries.map(\.id) }
    }

    /// Bought, and not yet put into the pantry.
    private var boughtToStock: [ShoppingEntry] {
        list.rows.filter { $0.item.isChecked && $0.item.stockedAt == nil }
    }

    // MARK: - List

    @ViewBuilder private var content: some View {
        List {
            if list.query.sort.first?.key == .aisle {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.rows) { row($0) }
                    }
                }
                if !checkedRows.isEmpty {
                    Section("Куплено") {
                        ForEach(checkedRows) { row($0) }
                    }
                }
            } else if list.query.sort.first?.key == .manual {
                ForEach(list.rows) { row($0) }
                    .onMove { source, destination in move(from: source, to: destination) }
            } else {
                ForEach(list.rows) { row($0) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .id(list.generation)
    }

    /// What is still to buy, by aisle in the shop's order.
    private var sections: [AisleSection<ShoppingEntry>] {
        let names = Dictionary(uniqueKeysWithValues: aisles.map { ($0.id, $0.name) })
        let unchecked = list.rows.filter { !$0.item.isChecked }
        return AisleSection.group(unchecked, aisle: { $0.product?.aisleID }, names: names, other: "Другое")
    }

    private var checkedRows: [ShoppingEntry] {
        list.rows.filter(\.item.isChecked)
    }

    private func row(_ entry: ShoppingEntry) -> some View {
        ShoppingRow(entry: entry) { checked in
            check(entry, checked)
        }
        .onAppear { list.rowAppeared(entry.id) }
        .contextMenu {
            Button("Изменить количество…") { editing = entry }
            if entry.item.isChecked, entry.item.stockedAt == nil, entry.product != nil {
                Button("Убрать в запасы…") { stocking = [entry] }
            }
            Divider()
            Button("Удалить", role: .destructive) { run { try database.removeShoppingItems([entry.id]) } }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if list.isLoaded, list.total == 0 {
            if list.query.text.isEmpty, list.query.filterCount == 0 {
                ContentUnavailableView {
                    Label("Список пуст", systemImage: "cart")
                } description: {
                    Text(
                        "Впишите, что купить, в строку сверху, или откройте рецепт и нажмите «Недостающее в покупки»."
                    )
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

    private var sortMenu: some View {
        Menu {
            Picker("Сортировать по", selection: sortKey) {
                ForEach(ShoppingQuery.SortKey.allCases, id: \.self) { key in
                    Text(key.title).tag(key)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Сортировка", systemImage: "arrow.up.arrow.down")
        }
    }

    private var sortKey: Binding<ShoppingQuery.SortKey> {
        Binding {
            list.query.sort.first?.key ?? .aisle
        } set: { key in
            list.query.sort = [SortTerm(key, key == .createdAt ? .descending : .ascending)]
        }
    }

    /// The list as text for Messages or Notes: by aisle, with amounts and dishes.
    private var shareText: String {
        let names = Dictionary(uniqueKeysWithValues: aisles.map { ($0.id, $0.name) })
        let open = list.rows.filter { !$0.item.isChecked }
        var lines = ["Покупки"]
        for section in AisleSection.group(open, aisle: { $0.product?.aisleID }, names: names, other: "Другое") {
            lines.append("")
            lines.append(section.title)
            lines += section.rows.map { "— " + ShoppingRow.title(of: $0) }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Changes

    /// «молоко 1 л» adds a product of the base; a name it does not know becomes a line of text.
    private func add(_ line: String) {
        run {
            var additions: [ShoppingAddition] = []
            for typed in try database.readLines(line) {
                if case .found(let product) = typed.match {
                    additions.append(ShoppingAddition(product: product.id, amount: typed.amount, unit: typed.unit))
                } else {
                    let text = typed.name.prefix(1).uppercased() + typed.name.dropFirst()
                    additions.append(ShoppingAddition(text: text, amount: typed.amount, unit: typed.unit))
                }
            }
            if additions.isEmpty {
                additions = [ShoppingAddition(text: line)]
            }
            try database.addToShopping(additions)
        }
    }

    private func check(_ entry: ShoppingEntry, _ checked: Bool) {
        run {
            try database.setChecked(checked, items: [entry.id])
            if checked, stocksWithoutAsking, entry.product != nil {
                try database.stockBought([entry.id: entry.amountInBaseUnit], keepOnList: true)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = list.rows.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        run { try database.reorderShopping(ids) }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            problem = String(describing: error)
        }
    }
}

/// One thing to buy: a checkbox, «Молоко — 545 мл», and for which dishes.
struct ShoppingRow: View {
    let entry: ShoppingEntry
    let setChecked: (Bool) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle(isOn: Binding(get: { entry.item.isChecked }, set: { setChecked($0) })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(of: entry))
                    .strikethrough(entry.item.isChecked)
                    .foregroundStyle(entry.item.isChecked ? Color(.textSecondary) : Color(.textPrimary))
                let dishes = entry.item.reasons.map(\.title)
                if !dishes.isEmpty {
                    Text("для: " + Self.unique(dishes).joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(Color(.textSecondary))
                        .lineLimit(1)
                }
            }
            Spacer()
            if entry.item.stockedAt != nil {
                Label("В запасах", systemImage: "refrigerator")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color(.textSecondary))
                    .help("Уже в запасах")
            }
        }
        .padding(.vertical, 2)
    }

    /// «Молоко — 545 мл», «Хлеб».
    static func title(of entry: ShoppingEntry) -> String {
        guard let amount = entry.item.amount else { return entry.name }
        return "\(entry.name) — \(Formatting.quantity(amount, entry.item.unit ?? .piece))"
    }

    private static func unique(_ titles: [String]) -> [String] {
        var seen: Set<String> = []
        return titles.filter { seen.insert($0).inserted }
    }
}

/// How much of one thing to buy.
struct ShoppingAmountEditor: View {
    let entry: ShoppingEntry
    let save: (Double?, MeasureUnit?) -> Void

    @State private var amount: Double?
    @State private var unit: MeasureUnit = .piece

    var body: some View {
        Form {
            TextField("Сколько", value: $amount, format: Formatting.decimal)
            Picker("Единица", selection: $unit) {
                ForEach(MeasureUnit.allCases.filter { $0.kind != .unmeasured }, id: \.self) { unit in
                    Text(unit.symbol).tag(unit)
                }
            }
            HStack {
                Spacer()
                Button("Без количества") { save(nil, nil) }
                Button("Готово") { save(amount, unit) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            amount = entry.item.amount
            unit = entry.item.unit ?? entry.product?.baseUnit.unit ?? .piece
        }
    }
}

/// «Купленное — в запасы»: every bought item with the amount it adds, which can be corrected or left out.
struct StockBoughtSheet: View {
    let entries: [ShoppingEntry]
    let stock: ([ShoppingItem.ID: Double?]) -> Void
    let dismissOnly: (Set<ShoppingItem.ID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amounts: [ShoppingItem.ID: Double?] = [:]
    @State private var included: Set<ShoppingItem.ID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Купленное — в запасы")
                .font(.title2.bold())
                .padding([.horizontal, .top], 20)
            Text("Количества можно поправить; без количества продукт просто отметится как имеющийся.")
                .foregroundStyle(Color(.textSecondary))
                .padding(.horizontal, 20)
                .padding(.top, 4)
            List(entries) { entry in
                HStack(spacing: 10) {
                    Toggle(
                        isOn: Binding(
                            get: { included.contains(entry.id) },
                            set: { isOn in
                                if isOn { included.insert(entry.id) } else { included.remove(entry.id) }
                            })
                    ) {
                        EmptyView()
                    }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(entry.product == nil)
                    Text(entry.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let product = entry.product {
                        TextField(
                            "есть", value: Binding(get: { amounts[entry.id] ?? nil }, set: { amounts[entry.id] = $0 }),
                            format: Formatting.decimal
                        )
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        Text(product.baseUnit.unit.symbol)
                            .foregroundStyle(Color(.textSecondary))
                            .frame(width: 30, alignment: .leading)
                    } else {
                        Text("не продукт базы")
                            .foregroundStyle(Color(.textSecondary))
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                Button("Только убрать из списка") {
                    dismissOnly(Set(entries.map(\.id)))
                    dismiss()
                }
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("В запасы") {
                    var chosen = amounts.filter { included.contains($0.key) }
                    for entry in entries where entry.product == nil {
                        chosen[entry.id] = nil as Double?
                    }
                    stock(chosen)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 520, height: 460)
        .onAppear {
            for entry in entries {
                amounts[entry.id] = entry.amountInBaseUnit
                if entry.product != nil { included.insert(entry.id) }
            }
        }
    }
}

extension ShoppingQuery.SortKey {
    var title: String {
        switch self {
        case .aisle: "По отделам магазина"
        case .name: "Название"
        case .createdAt: "Сначала новые"
        case .manual: "Свой порядок"
        }
    }
}

/// The shopping list's filters: aisles, bought or not, and the dish an item is for.
struct ShoppingFilterBar: View {
    @Binding var query: ShoppingQuery
    let aisles: [Aisle]
    let recipes: [Recipe.ID: String]

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Menu("Отдел") {
                    ForEach(aisles) { aisle in
                        Toggle(
                            aisle.name,
                            isOn: Binding(
                                get: { query.aisleIDs.contains(aisle.id) },
                                set: { isOn in
                                    if isOn { query.aisleIDs.insert(aisle.id) } else { query.aisleIDs.remove(aisle.id) }
                                }))
                    }
                }
                Menu("Куплено") { checkedChoices }
                Menu("Для блюда") { recipeChoices }
            } label: {
                Label("Фильтр", systemImage: "line.3.horizontal.decrease")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .chipBackground()

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if !query.aisleIDs.isEmpty {
                        FilterChip(
                            title: "Отдел",
                            value: aisles.filter { query.aisleIDs.contains($0.id) }.map(\.name).joined(separator: ", ")
                        ) {
                            query.aisleIDs = []
                        } options: {
                            EmptyView()
                        }
                    }
                    if let isChecked = query.isChecked {
                        FilterChip(title: "Куплено", value: isChecked ? "да" : "нет") {
                            query.isChecked = nil
                        } options: {
                            checkedChoices
                        }
                    }
                    if let recipeID = query.recipeID {
                        FilterChip(title: "Для блюда", value: recipes[recipeID] ?? "…") {
                            query.recipeID = nil
                        } options: {
                            recipeChoices
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            if query.filterCount > 0 {
                Button("Сбросить") { query = query.withoutFilters }
                    .buttonStyle(.link)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var checkedChoices: some View {
        Picker("Куплено", selection: $query.isChecked) {
            Text("Ещё купить").tag(Bool?.some(false))
            Text("Куплено").tag(Bool?.some(true))
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    @ViewBuilder private var recipeChoices: some View {
        Picker("Для блюда", selection: $query.recipeID) {
            ForEach(recipes.sorted { $0.value < $1.value }, id: \.key) { id, title in
                Text(title).tag(Recipe.ID?.some(id))
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
