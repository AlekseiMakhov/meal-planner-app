import MealCore
import MealStore
import SwiftUI

/// What there is at home, by aisle: amounts to type or step, staples as «есть / закончилось», a mark for what is
/// running low, and a line to type what was found or bought.
struct PantryScreen: View {
    let database: AppDatabase

    @Environment(AppModel.self) private var model
    @State private var list: PagedList<PantryQuery, PantryEntry>
    @State private var aisles: [Aisle] = []
    @State private var searchText = ""
    @State private var picking: Pick?
    @State private var notice: String?
    @State private var problem: String?
    @State private var keeping: PantryEntry?
    @State private var keepText = ""

    /// A product to choose for a typed line the base did not settle: none or several fit.
    struct Pick: Identifiable {
        let id = UUID()
        var text = ""
        var amount: Double?
        var unit: MeasureUnit?
    }

    init(database: AppDatabase) {
        self.database = database
        _list = State(
            initialValue: PagedList(query: PantryQuery()) { query, limit in
                database.observePantry(query, limit: limit)
            })
    }

    var body: some View {
        @Bindable var list = list
        VStack(spacing: 0) {
            QuickAddField(prompt: "Добавить в запасы: «яйца 10», «молоко 1 л», «соль»", onSubmit: add)
            Divider()
            PantryFilterBar(query: $list.query, aisles: aisles)
            Divider()
            content
                .overlay { emptyState }
            Divider()
            HStack {
                ListFooter(shown: list.rows.count, total: list.total, noun: ("продукт", "продукта", "продуктов"))
                if let notice {
                    Text(notice)
                        .font(.callout)
                        .foregroundStyle(Color(.textSecondary))
                        .padding(.trailing, 12)
                        .transition(.opacity)
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Продукт")
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
        .onDisappear { list.stop() }
        .onChange(of: model.request, initial: true) {
            guard let request = model.request, request.section == .pantry else { return }
            searchText = request.search ?? ""
            model.request = nil
        }
        .toolbar {
            ToolbarItemGroup {
                sortMenu
                Button("Добавить продукт", systemImage: "plus") { picking = Pick() }
            }
        }
        .popover(item: $picking, arrowEdge: .bottom) { pick in
            ProductPicker(database: database, prompt: "Какой продукт?", initialText: pick.text) { product in
                picking = nil
                add(product, amount: pick.amount, unit: pick.unit)
            }
        }
        .alert(
            "Держать дома: \(keeping?.product.name ?? "")", isPresented: isPresent($keeping), presenting: keeping
        ) { entry in
            TextField(entry.product.baseUnit.unit.symbol, text: $keepText)
            Button("Сохранить") {
                let value = Double(
                    keepText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
                run { try database.setPantryMinimum(value, productID: entry.product.id) }
            }
            Button("Не следить") { run { try database.setPantryMinimum(nil, productID: entry.product.id) } }
            Button("Отмена", role: .cancel) {}
        } message: { entry in
            Text(
                "Сколько держать дома, в \(entry.product.baseUnit.unit.symbol). Когда станет меньше, недостающее само попадёт в покупки."
            )
        }
        .alert("Не получилось", isPresented: isPresent($problem), presenting: problem) { _ in
            Button("Понятно") {}
        } message: { problem in
            Text(problem)
        }
    }

    // MARK: - List

    @ViewBuilder private var content: some View {
        List {
            if list.query.sort.first?.key == .aisle {
                let names = Dictionary(uniqueKeysWithValues: aisles.map { ($0.id, $0.name) })
                ForEach(AisleSection.group(list.rows, aisle: { $0.product.aisleID }, names: names)) { section in
                    Section(section.title) {
                        ForEach(section.rows) { row($0) }
                    }
                }
            } else {
                ForEach(list.rows) { row($0) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .id(list.generation)
    }

    private func row(_ entry: PantryEntry) -> some View {
        PantryRow(entry: entry) { quantity in
            run { try database.setPantry(entry.product.id, quantity: quantity) }
        } setLow: { isLow in
            run { try database.setLow(isLow, productID: entry.product.id) }
        }
        .onAppear { list.rowAppeared(entry.id) }
        .contextMenu {
            Button("В покупки") {
                run {
                    try database.addToShopping([ShoppingAddition(product: entry.product.id)])
                    show("«\(entry.product.name)» — в покупках")
                }
            }
            Button(entry.item.isLow ? "Хватает" : "Заканчивается") {
                run { try database.setLow(!entry.item.isLow, productID: entry.product.id) }
            }
            Button("Закончилось") { run { try database.setPantry(entry.product.id, quantity: 0) } }
            Button("Держать дома…") {
                keepText = entry.item.minimum.map { Formatting.number($0, digits: 2) } ?? ""
                keeping = entry
            }
            Divider()
            Button("Убрать из запасов", role: .destructive) {
                run { try database.removeFromPantry([entry.product.id]) }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if list.isLoaded, list.total == 0 {
            if list.query.text.isEmpty, list.query.filterCount == 0 {
                ContentUnavailableView {
                    Label("Запасов пока нет", systemImage: "refrigerator")
                } description: {
                    Text("Впишите, что есть дома, в строку сверху: «яйца 10», «молоко 1 л», «соль».")
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
                ForEach(PantryQuery.SortKey.allCases, id: \.self) { key in
                    Text(key.title).tag(key)
                }
            }
            .pickerStyle(.inline)
            Picker("Порядок", selection: sortDirection) {
                Text("По возрастанию").tag(SortDirection.ascending)
                Text("По убыванию").tag(SortDirection.descending)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Сортировка", systemImage: "arrow.up.arrow.down")
        }
    }

    private var sortKey: Binding<PantryQuery.SortKey> {
        Binding {
            list.query.sort.first?.key ?? .aisle
        } set: { key in
            list.query.sort = [SortTerm(key, list.query.sort.first?.direction ?? .ascending)]
        }
    }

    private var sortDirection: Binding<SortDirection> {
        Binding {
            list.query.sort.first?.direction ?? .ascending
        } set: { direction in
            list.query.sort = [SortTerm(list.query.sort.first?.key ?? .aisle, direction)]
        }
    }

    // MARK: - Adding

    /// «яйца 10» adds ten eggs; a name the base does not settle opens the product list to choose from.
    private func add(_ line: String) {
        run {
            for typed in try database.readLines(line) {
                switch typed.match {
                case .found(let product):
                    add(product, amount: typed.amount, unit: typed.unit)
                case .ambiguous, .none:
                    picking = Pick(text: typed.name, amount: typed.amount, unit: typed.unit)
                    return
                }
            }
        }
    }

    private func add(_ product: Product, amount: Double?, unit: MeasureUnit?) {
        run {
            let converted = amount.flatMap { product.units.inBaseUnit($0, unit ?? .piece) }
            try database.addToPantry([product.id: converted])
            if let amount, converted == nil {
                let written = Formatting.quantity(amount, unit ?? .piece)
                show(
                    "«\(product.name)»: \(written) не пересчитать в \(product.baseUnit.unit.symbol), отмечено, что есть"
                )
            } else if let converted {
                show("«\(product.name)»: +\(Formatting.quantity(converted, product.baseUnit.unit))")
            } else {
                show("«\(product.name)» — есть")
            }
        }
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { if notice == text { notice = nil } }
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            problem = String(describing: error)
        }
    }
}

/// A product at home: its status, the amount or «есть / закончилось» for a staple, and the «заканчивается» mark.
struct PantryRow: View {
    let entry: PantryEntry
    let setQuantity: (Double?) -> Void
    let setLow: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            PantryDot(status: entry.item.status)
            Text(entry.product.name)
                .foregroundStyle(entry.item.isInStock ? Color(.textPrimary) : Color(.textSecondary))
                .frame(maxWidth: .infinity, alignment: .leading)
            if entry.product.isStaple {
                Picker(
                    "Есть дома",
                    selection: Binding(get: { entry.item.isInStock }, set: { setQuantity($0 ? nil : 0) })
                ) {
                    Text("Есть").tag(true)
                    Text("Закончилось").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            } else {
                if let minimum = entry.item.minimum {
                    Text("держать \(Formatting.quantity(minimum, entry.product.baseUnit.unit))")
                        .font(.caption)
                        .foregroundStyle(entry.item.isBelowMinimum ? Color(.statusLow) : Color(.textSecondary))
                }
                QuantityField(value: entry.item.quantity, unit: entry.product.baseUnit.unit, commit: setQuantity)
            }
            Toggle(isOn: Binding(get: { entry.item.isLow }, set: { setLow($0) })) {
                Label("Заканчивается", systemImage: entry.item.isLow ? "battery.25percent" : "battery.100percent")
                    .labelStyle(.iconOnly)
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .foregroundStyle(entry.item.isLow ? Color(.statusLow) : Color(.textSecondary))
            .help(entry.item.isLow ? "Заканчивается" : "Отметить, что заканчивается")
        }
        .padding(.vertical, 2)
    }
}

extension PantryQuery.SortKey {
    var title: String {
        switch self {
        case .aisle: "Отдел"
        case .name: "Название"
        case .quantity: "Количество"
        case .updatedAt: "Дата изменения"
        }
    }
}

/// The pantry's filters: aisles and status.
struct PantryFilterBar: View {
    @Binding var query: PantryQuery
    let aisles: [Aisle]

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Menu("Отдел") { aisleToggles }
            } label: {
                Label("Фильтр", systemImage: "line.3.horizontal.decrease")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .chipBackground()

            ForEach(PantryStatus.allCases, id: \.self) { status in
                Toggle(status.title, isOn: membership(status))
                    .toggleStyle(.button)
                    .controlSize(.small)
            }
            Toggle("Для меню недели", isOn: forMenu)
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Продукты, которые нужны блюдам меню на этой неделе, начиная с сегодня")

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if !query.aisleIDs.isEmpty {
                        FilterChip(
                            title: "Отдел",
                            value: aisles.filter { query.aisleIDs.contains($0.id) }.map(\.name).joined(separator: ", ")
                        ) {
                            query.aisleIDs = []
                        } options: {
                            aisleToggles
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

    @ViewBuilder private var aisleToggles: some View {
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

    /// The rest of this week's menu, from today.
    private var forMenu: Binding<Bool> {
        Binding {
            query.menuDays != nil
        } set: { isOn in
            let today = Day.today()
            query.menuDays = isOn ? today...today.weekStart.adding(days: 6) : nil
        }
    }

    private func membership(_ status: PantryStatus) -> Binding<Bool> {
        Binding {
            query.statuses.contains(status)
        } set: { isOn in
            if isOn { query.statuses.insert(status) } else { query.statuses.remove(status) }
        }
    }
}
