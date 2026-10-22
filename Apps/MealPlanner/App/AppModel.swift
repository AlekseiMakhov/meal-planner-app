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

    /// Something that stops the app from working, told in the window.
    struct Problem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var section: Section = .recipes
    var problem: Problem?

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
            database = try AppDatabase.open(in: dataDirectory)
        } catch {
            problem = Problem(title: "Не открылась база данных", message: "\(error)")
        }
    }
}
