import AppKit
import MealCore
import MealStore
import SwiftUI

/// The main window: sections and recipe categories in the sidebar, each with its own screen.
struct MainWindow: View {
    static let id = "main"

    @Environment(AppModel.self) private var model
    @State private var categories: [CategorySummary] = []
    @State private var shoppingCount = 0
    @State private var naming: CategoryNaming?
    @State private var name = ""
    @State private var deleting: RecipeCategory?
    @State private var categoryProblem: String?
    @State private var claudeNotice: String?

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(
                selection: Binding<AppModel.SidebarItem?>(
                    get: { model.sidebar }, set: { item in item.map { model.sidebar = $0 } })
            ) {
                Section {
                    ForEach(AppModel.Section.allCases) { section in
                        sectionRow(section)
                    }
                }
                Section {
                    ForEach(categories) { summary in
                        Label {
                            Text(summary.category.name)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(summary.category.color.color)
                                .imageScale(.small)
                        }
                        .badge(summary.count)
                        .tag(AppModel.SidebarItem.category(summary.id))
                        .contextMenu { categoryMenu(summary.category) }
                    }
                    .onMove(perform: moveCategories)
                } header: {
                    HStack {
                        Text("Категории")
                        Spacer()
                        Button("Новая категория", systemImage: "plus") { name(.new) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            SectionScreen(section: model.section, category: model.category, database: model.database)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.canvas))
        }
        .navigationTitle(title)
        .containerBackground(Color(.canvas), for: .window)
        .task {
            guard let database = model.database else { return }
            do {
                for try await categories in database.observeCategories() {
                    self.categories = categories
                    if let selected = model.category, !categories.contains(where: { $0.id == selected }) {
                        model.sidebar = .section(.recipes)
                    }
                }
            } catch {
                categoryProblem = String(describing: error)
            }
        }
        .task {
            guard let database = model.database else { return }
            do {
                for try await count in database.observeShoppingCount() { shoppingCount = count }
            } catch {
                categoryProblem = String(describing: error)
            }
        }
        .alert(naming?.title ?? "", isPresented: isPresent($naming), presenting: naming) { naming in
            TextField("Название", text: $name)
            Button("Сохранить") { save(naming) }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog(
            "Удалить категорию «\(deleting?.name ?? "")»?", isPresented: isPresent($deleting), presenting: deleting
        ) { category in
            Button("Удалить", role: .destructive) { delete(category) }
        } message: { _ in
            Text("Рецепты останутся — в других категориях или без категории.")
        }
        .alert("Не получилось", isPresented: isPresent($categoryProblem), presenting: categoryProblem) { _ in
            Button("Понятно") {}
        } message: { problem in
            Text(problem)
        }
        .alert(
            "Подключить Meal Planner к Claude?", isPresented: isPresent($model.claudeRequestAwaitingConnection),
            presenting: model.claudeRequestAwaitingConnection
        ) { request in
            Button("Подключить") { connectClaude(then: request) }
            Button("Отмена", role: .cancel) {}
        } message: { _ in
            Text(
                "Без инструментов Meal Planner Claude не прочитает и не изменит рецепты. В конфиг Claude Desktop добавится сервер «\(ClaudeConnection.current.serverName)», прежний конфиг сохранится рядом."
            )
        }
        .sheet(isPresented: $model.showsQuickSearch) {
            if let database = model.database {
                QuickSearch(database: database) { hit in model.open(hit) }
            }
        }
        .alert("Claude", isPresented: isPresent($claudeNotice), presenting: claudeNotice) { _ in
            Button("Понятно") {}
        } message: { notice in
            Text(notice)
        }
        .alert(
            model.problem?.title ?? "",
            isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } }),
            presenting: model.problem
        ) { _ in
            Button("Понятно") { model.problem = nil }
        } message: { problem in
            Text(problem.message)
        }
    }

    private var title: String {
        if let id = model.category, let category = categories.first(where: { $0.id == id }) {
            return category.category.name
        }
        return model.section.title
    }

    /// A section of the sidebar; «Покупки» counts what is still to buy.
    private func sectionRow(_ section: AppModel.Section) -> some View {
        let badge = section == .shopping ? shoppingCount : 0
        return Label(section.title, systemImage: section.symbol)
            .badge(badge)
            .tag(AppModel.SidebarItem.section(section))
    }

    @ViewBuilder private func categoryMenu(_ category: RecipeCategory) -> some View {
        Button("Переименовать…") { name(.rename(category)) }
        Menu("Цвет") {
            ForEach(TagColor.allCases, id: \.self) { color in
                Toggle(
                    color.title, isOn: Binding(get: { category.color == color }, set: { _ in recolor(category, color) })
                )
            }
        }
        Divider()
        Button("Удалить…", role: .destructive) { deleting = category }
    }

    // MARK: - Changes

    /// Adds the server to Claude Desktop's config. A running Claude Desktop sees it only after a restart, so the
    /// request waits for the next press; otherwise it goes now and Claude Desktop starts with the server.
    private func connectClaude(then request: String) {
        do {
            try ClaudeConnection.current.install()
        } catch {
            claudeNotice = "Конфиг Claude Desktop не изменился: \(error)."
            return
        }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: ClaudeHandoff.bundleID).isEmpty
        if running {
            claudeNotice =
                "Meal Planner подключён. Перезапустите Claude Desktop — ⌘Q и открыть снова, — чтобы он увидел инструменты, и нажмите кнопку ещё раз."
        } else {
            ClaudeHandoff.send(request, workspace: model.claudeWorkspace)
        }
    }

    private enum CategoryNaming: Identifiable {
        case new
        case rename(RecipeCategory)

        var id: String {
            switch self {
            case .new: "new"
            case .rename(let category): "rename \(category.id)"
            }
        }

        var title: String {
            switch self {
            case .new: "Новая категория"
            case .rename: "Переименовать категорию"
            }
        }
    }

    private func name(_ naming: CategoryNaming) {
        if case .rename(let category) = naming {
            name = category.name
        } else {
            name = ""
        }
        self.naming = naming
    }

    private func save(_ naming: CategoryNaming) {
        guard let database = model.database else { return }
        do {
            switch naming {
            case .new:
                let category = try database.newCategory(named: name)
                model.sidebar = .category(category.id)
            case .rename(var category):
                category.name = name
                try database.save(category)
            }
        } catch {
            categoryProblem = String(describing: error)
        }
    }

    private func recolor(_ category: RecipeCategory, _ color: TagColor) {
        var category = category
        category.color = color
        do {
            try model.database?.save(category)
        } catch {
            categoryProblem = String(describing: error)
        }
    }

    private func delete(_ category: RecipeCategory) {
        do {
            try model.database?.deleteCategory(id: category.id)
        } catch {
            categoryProblem = String(describing: error)
        }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var ids = categories.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        do {
            try model.database?.reorderCategories(ids)
        } catch {
            categoryProblem = String(describing: error)
        }
    }
}

/// True while the optional holds a value; setting false clears it. For alerts and sheets that present a value.
@MainActor
func isPresent<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
    Binding {
        value.wrappedValue != nil
    } set: {
        if !$0 { value.wrappedValue = nil }
    }
}
