import AppKit
import MealCore
import MealStore
import SwiftUI

/// The week's menu: days across, meals down, dishes in the cells. Recipes are dragged in from the list beside it,
/// dishes between cells — with ⌥ as copies — and ⌫ takes the chosen ones off. Under each day, what it adds up to.
struct PlannerScreen: View {
    let database: AppDatabase

    @Environment(AppModel.self) private var model
    @AppStorage("planner.showsLibrary") private var showsLibrary = true
    @AppStorage("planner.perPerson") private var showsPerPerson = true
    @AppStorage("planner.total") private var showsTotal = false
    @AppStorage("planner.macros") private var showsMacros = true
    @AppStorage("planner.collapsed") private var collapsedText = ""
    @State private var weekStart = Day.today().weekStart
    @State private var plan: WeekPlan?
    @State private var selection: Set<PlanEntry.ID> = []
    @State private var adding: CellTarget?
    @State private var cooking: CookingRequest?
    @State private var opened: OpenedRecipe?
    @State private var categories: [RecipeCategory] = []
    @State private var naming: MealNaming?
    @State private var mealName = ""
    @State private var notice: String?
    @State private var problem: String?

    private static let labelWidth: CGFloat = 104

    /// `plan` is shown until the database answers: for previews.
    init(database: AppDatabase, plan: WeekPlan? = nil) {
        self.database = database
        _plan = State(initialValue: plan)
        if let plan {
            _weekStart = State(initialValue: plan.start)
        }
    }

    struct CellTarget: Identifiable, Equatable {
        let day: Day
        let meal: MealType

        var id: String {
            "\(day)-\(meal.id)"
        }
    }

    struct CookingRequest: Identifiable {
        let entry: PlanEntry
        let title: String
        let use: [CookingUse]

        var id: PlanEntry.ID {
            entry.id
        }
    }

    struct OpenedRecipe: Identifiable {
        let id: Recipe.ID
    }

    enum MealNaming: Identifiable {
        case new
        case rename(MealType)

        var id: String {
            switch self {
            case .new: "new"
            case .rename(let meal): "rename \(meal.id)"
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                if let plan {
                    grid(plan, width: geometry.size.width)
                        .padding(16)
                } else {
                    ProgressView()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .background(Color(.canvas))
        .focusable()
        .focusEffectDisabled()
        .onDeleteCommand { remove(selection) }
        .overlay(alignment: .bottom) { noticeView }
        .toolbar { toolbar }
        .navigationTitle("Неделя \(weekStart.weekNumber) · \(Formatting.week(weekStart))")
        .inspector(isPresented: $showsLibrary) {
            PlannerLibrary(database: database, mealTypes: plan?.mealTypes ?? [])
                .inspectorColumnWidth(min: 250, ideal: 290, max: 400)
        }
        .task(id: weekStart) {
            selection = []
            do {
                for try await plan in database.observeWeekPlan(starting: weekStart) { self.plan = plan }
            } catch {
                problem = String(describing: error)
            }
        }
        .task {
            do {
                for try await summaries in database.observeCategories() { categories = summaries.map(\.category) }
            } catch {
                problem = String(describing: error)
            }
        }
        .popover(item: $adding, arrowEdge: .bottom) { target in
            PlanQuickAdd(database: database, meal: target.meal) { recipe, text in
                adding = nil
                run { try database.planMeal(on: target.day, meal: target.meal.id, recipe: recipe, text: text) }
            }
        }
        .sheet(item: $cooking) { request in
            CookedSheet(title: request.title, use: request.use) { amounts in
                run { try database.markCooked(request.entry.id, using: amounts) }
            }
        }
        .sheet(item: $opened) { recipe in
            NavigationStack {
                RecipePage(
                    database: database, route: RecipeRoute(id: recipe.id), categories: categories,
                    mealTypes: plan?.mealTypes ?? []
                ) {
                    opened = nil
                }
            }
            .environment(model)
            .frame(minWidth: 820, minHeight: 640)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { opened = nil }
                }
            }
        }
        .alert(
            namingTitle, isPresented: isPresent($naming), presenting: naming
        ) { naming in
            TextField("Название", text: $mealName)
            Button("Сохранить") { saveMeal(naming) }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Не получилось", isPresented: isPresent($problem), presenting: problem) { _ in
            Button("Понятно") {}
        } message: { problem in
            Text(problem)
        }
    }

    // MARK: - Grid

    private func grid(_ plan: WeekPlan, width: CGFloat) -> some View {
        let column = max(112, (width - 32 - Self.labelWidth - 7 * 8) / 7)
        let today = Day.today()
        let supply = plan.supply(from: max(today, plan.start))
        return Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                newMealButton
                    .frame(width: Self.labelWidth, alignment: .leading)
                ForEach(plan.days, id: \.self) { day in
                    DayHeader(day: day, isToday: day == today)
                        .frame(width: column)
                }
            }
            ForEach(plan.mealTypes) { meal in
                GridRow {
                    mealLabel(meal)
                        .frame(width: Self.labelWidth, alignment: .leading)
                        .padding(.top, 6)
                    ForEach(plan.days, id: \.self) { day in
                        if collapsed.contains(meal.id) {
                            collapsedCell(plan.entries(on: day, meal: meal.id).count)
                                .frame(width: column)
                        } else {
                            PlanCell(
                                day: day, meal: meal, entries: plan.entries(on: day, meal: meal.id), plan: plan,
                                shortEntries: supply.shortEntries, selection: selection, width: column,
                                images: database.images, actions: actions)
                        }
                    }
                }
            }
            Divider()
                .gridCellUnsizedAxes(.horizontal)
            GridRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Итого")
                        .font(.headline)
                    if let average = plan.averageDay {
                        Text("в среднем \(Formatting.number(average.perPerson.kcal, digits: 0)) ккал")
                            .font(.caption)
                            .foregroundStyle(Color(.textSecondary))
                            .help("На человека за день, по дням, где что-то запланировано")
                    }
                }
                .frame(width: Self.labelWidth, alignment: .leading)
                ForEach(plan.days, id: \.self) { day in
                    DayTotals(
                        nutrition: plan.nutrition(on: day), showsPerPerson: showsPerPerson, showsTotal: showsTotal,
                        showsMacros: showsMacros
                    )
                    .frame(width: column, alignment: .leading)
                }
            }
        }
    }

    private func mealLabel(_ meal: MealType) -> some View {
        HStack(spacing: 6) {
            Button {
                toggleCollapsed(meal.id)
            } label: {
                Image(systemName: collapsed.contains(meal.id) ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(.textSecondary))
            .help(collapsed.contains(meal.id) ? "Развернуть" : "Свернуть")
            TagView(name: meal.name, color: meal.color)
        }
        .contextMenu {
            Button("Переименовать…") {
                mealName = meal.name
                naming = .rename(meal)
            }
            Menu("Цвет") {
                ForEach(TagColor.allCases, id: \.self) { color in
                    Toggle(color.title, isOn: Binding(get: { meal.color == color }, set: { _ in recolor(meal, color) }))
                }
            }
            Divider()
            Button("Удалить…", role: .destructive) {
                run { try database.deleteMealType(id: meal.id) }
            }
        }
    }

    private var newMealButton: some View {
        Button {
            mealName = ""
            naming = .new
        } label: {
            Label("Приём пищи", systemImage: "plus")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(.textSecondary))
        .help("Добавить свой приём пищи: «Второй завтрак», «Полдник»")
    }

    private func collapsedCell(_ count: Int) -> some View {
        Text(count == 0 ? "—" : Formatting.count(count, "блюдо", "блюда", "блюд"))
            .font(.caption)
            .foregroundStyle(Color(.textSecondary))
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(Color(.surface), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private var noticeView: some View {
        if let notice {
            Text(notice)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .transition(.opacity)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Предыдущая неделя", systemImage: "chevron.left") { weekStart = weekStart.adding(days: -7) }
            Button("Следующая неделя", systemImage: "chevron.right") { weekStart = weekStart.adding(days: 7) }
        }
        ToolbarItemGroup {
            Button("Сегодня") { weekStart = Day.today().weekStart }
                .disabled(weekStart == Day.today().weekStart)
            Button("Покупки на неделю", systemImage: "cart.badge.plus", action: buyForWeek)
                .help("Положить в покупки то, чего не хватит на блюда недели, начиная с сегодняшнего дня")
            Menu("Ещё", systemImage: "ellipsis.circle") {
                Button("Составить меню с Claude…", systemImage: "sparkles") {
                    model.askClaude(ClaudeRequest.planWeek(week: weekStart.description, wishes: nil))
                }
                Button("Скопировать прошлую неделю", action: copyLastWeek)
                Button("PDF меню в iCloud Drive", systemImage: "doc.richtext", action: exportPDF)
                    .disabled(plan?.entries.isEmpty ?? true)
                Divider()
                Toggle("На человека", isOn: $showsPerPerson)
                Toggle("Всего, на все порции", isOn: $showsTotal)
                Toggle("Белки, жиры, углеводы", isOn: $showsMacros)
            }
            Button("Рецепты", systemImage: "sidebar.trailing") { showsLibrary.toggle() }
        }
    }

    // MARK: - Actions

    private var actions: PlanActions {
        PlanActions(
            drop: drop, select: select,
            open: { entry in
                if let id = entry.recipeID { opened = OpenedRecipe(id: id) }
            },
            setServings: { entry, servings in run { try database.setPlanServings(servings, entry: entry.id) } },
            cook: cook,
            undoCooked: { entry in run { try database.undoCooked(entry.id) } },
            repeatOn: { entry, day in run { try database.copyPlanEntry(entry.id, to: day, meal: entry.mealTypeID) } },
            remove: { entry in remove([entry.id]) },
            add: { day, meal in
                if let meal = plan?.mealTypes.first(where: { $0.id == meal }) {
                    adding = CellTarget(day: day, meal: meal)
                }
            })
    }

    /// A recipe from the list becomes a dish; a dish moves, or with ⌥ held is copied.
    private func drop(_ items: [PlanDragItem], _ day: Day, _ meal: MealType.ID, _ before: PlanEntry.ID?) {
        let copies = NSEvent.modifierFlags.contains(.option)
        run {
            for item in items {
                switch item {
                case .recipe(let id):
                    let entry = try database.planMeal(on: day, meal: meal, recipe: id)
                    if let before { try database.movePlanEntry(entry.id, to: day, meal: meal, before: before) }
                case .entry(let id) where copies:
                    let copy = try database.copyPlanEntry(id, to: day, meal: meal)
                    if let before { try database.movePlanEntry(copy.id, to: day, meal: meal, before: before) }
                case .entry(let id):
                    guard id != before else { continue }
                    try database.movePlanEntry(id, to: day, meal: meal, before: before)
                }
            }
        }
    }

    private func select(_ id: PlanEntry.ID, _ adding: Bool) {
        if adding {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = selection == [id] ? [] : [id]
        }
    }

    private func remove(_ ids: Set<PlanEntry.ID>) {
        guard !ids.isEmpty else { return }
        run { try database.removePlanEntries(ids) }
        selection.subtract(ids)
    }

    private func cook(_ entry: PlanEntry) {
        guard let recipeID = entry.recipeID else { return }
        run {
            let use = try database.cookingUse(of: entry.id)
            let title = plan?.recipes[recipeID]?.recipe.title ?? "блюдо"
            cooking = CookingRequest(entry: entry, title: title, use: use)
        }
    }

    private func buyForWeek() {
        run {
            let added = try database.addMenuShortages(week: weekStart, from: max(Day.today(), weekStart))
            show(
                added.isEmpty
                    ? "На блюда недели всё есть или уже в покупках"
                    : "В покупках: \(Formatting.count(added.count, "позиция", "позиции", "позиций"))")
        }
    }

    private func copyLastWeek() {
        run {
            let count = try database.copyWeek(from: weekStart.adding(days: -7), to: weekStart)
            show(
                count == 0
                    ? "На прошлой неделе нечего копировать"
                    : "Скопировано: \(Formatting.count(count, "блюдо", "блюда", "блюд"))")
        }
    }

    /// The week and its recipes as a PDF in iCloud Drive, or wherever the save panel says without it.
    private func exportPDF() {
        guard let plan else { return }
        if let folder = MenuPDF.iCloudFolder {
            let file = folder.appending(path: MenuPDF.fileName(plan))
            run {
                try MenuPDF.write(plan, images: database.images, to: file)
                NSWorkspace.shared.activateFileViewerSelecting([file])
                show("PDF в iCloud Drive → Meal Planner")
            }
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = MenuPDF.fileName(plan)
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let file = panel.url else { return }
        run {
            try MenuPDF.write(plan, images: database.images, to: file)
            show("PDF сохранён")
        }
    }

    private var namingTitle: String {
        switch naming {
        case .rename: "Переименовать приём пищи"
        default: "Новый приём пищи"
        }
    }

    private func saveMeal(_ naming: MealNaming) {
        run {
            switch naming {
            case .new: try database.newMealType(named: mealName)
            case .rename(var meal):
                meal.name = mealName
                try database.save(meal)
            }
        }
    }

    private func recolor(_ meal: MealType, _ color: TagColor) {
        var meal = meal
        meal.color = color
        run { try database.save(meal) }
    }

    private var collapsed: Set<MealType.ID> {
        Set(collapsedText.split(separator: ",").compactMap { Int64($0) })
    }

    private func toggleCollapsed(_ id: MealType.ID) {
        var set = collapsed
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        collapsedText = set.sorted().map(String.init).joined(separator: ",")
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
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

/// «ПН 19», today stands out.
private struct DayHeader: View {
    let day: Day
    let isToday: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(Formatting.weekdays[day.weekday - 1])
                .foregroundStyle(Color(.textSecondary))
            Text("\(day.day)")
                .fontWeight(.semibold)
                .foregroundStyle(isToday ? Color.white : Color(.textPrimary))
                .padding(.horizontal, isToday ? 6 : 0)
                .background {
                    if isToday { Capsule().fill(Color.accentColor) }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(Formatting.day(day))
    }
}

/// What a day adds up to, as «Ещё» chooses to show: per person, for all servings, with or without macros.
private struct DayTotals: View {
    let nutrition: DayNutrition
    let showsPerPerson: Bool
    let showsTotal: Bool
    let showsMacros: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if nutrition.isEmpty {
                Text("—")
                    .foregroundStyle(Color(.textSecondary))
            } else {
                if showsPerPerson {
                    line(nutrition.perPerson, label: "на человека")
                }
                if showsTotal {
                    line(nutrition.total, label: "всего")
                }
                if nutrition.uncounted > 0 {
                    Text("без КБЖУ: \(nutrition.uncounted)")
                        .font(.caption)
                        .foregroundStyle(Color(.textSecondary))
                }
            }
        }
    }

    private func line(_ value: Nutrition, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(nutrition.uncounted > 0 ? "≈ " : "")\(Formatting.number(value.kcal, digits: 0)) ккал")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            if showsMacros {
                Text(
                    "Б \(Formatting.number(value.protein, digits: 0)) · Ж \(Formatting.number(value.fat, digits: 0)) · У \(Formatting.number(value.carbs, digits: 0))"
                )
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color(.textSecondary))
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color(.textSecondary))
        }
    }
}
