import Foundation
import MealCore
import MealStore
import Observation

/// What the window shows and the data it works with.
@MainActor @Observable
final class AppModel {
    /// The sidebar's sections, in its order.
    enum Section: String, CaseIterable, Identifiable {
        case recipes, planner, pantry, shopping, products

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .recipes: "Рецепты"
            case .planner: "Меню на неделю"
            case .pantry: "Запасы"
            case .shopping: "Покупки"
            case .products: "Продукты"
            }
        }

        var symbol: String {
            switch self {
            case .recipes: "book.closed"
            case .planner: "calendar"
            case .pantry: "refrigerator"
            case .shopping: "cart"
            case .products: "carrot"
            }
        }
    }

    /// What the sidebar has selected: a section, or one category of recipes.
    enum SidebarItem: Hashable {
        case section(Section)
        case category(RecipeCategory.ID)
    }

    /// Something that stops the app from working, told in the window.
    struct Problem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var sidebar = SidebarItem.section(.recipes)
    var problem: Problem?

    /// The section on screen; a category is the recipes section showing that category.
    var section: Section {
        get {
            if case .section(let section) = sidebar { section } else { .recipes }
        }
        set {
            sidebar = .section(newValue)
        }
    }

    var category: RecipeCategory.ID? {
        if case .category(let id) = sidebar { id } else { nil }
    }

    /// `~/Library/Application Support/inco.mealplanner`; a Debug build has a folder of its own.
    let dataDirectory: URL?
    private(set) var database: AppDatabase?

    static var isDebugBuild: Bool {
        AppIdentity.isDebug(bundleID: Bundle.main.bundleIdentifier ?? "")
    }

    init() {
        dataDirectory = try? AppDatabase.defaultDirectory(debug: Self.isDebugBuild)
        guard let dataDirectory else {
            problem = Problem(title: "Нет папки для данных", message: "Не нашлась папка Application Support.")
            return
        }
        do {
            let database = try AppDatabase.open(in: dataDirectory)
            self.database = database
            // What the trash and interrupted photo saves leave behind; the window does not wait for it.
            Task.detached(priority: .background) {
                _ = try? database.emptyTrash()
                _ = try? database.removeUnusedImages()
            }
        } catch {
            problem = Problem(title: "Не открылась база данных", message: "\(error)")
        }
    }
}
