import AppKit
import MealCore
import MealStore
import OSLog
import Observation
import os

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

    nonisolated static let log = Logger(subsystem: "inco.mealplanner", category: "app")

    var sidebar = SidebarItem.section(.recipes)
    var problem: Problem?
    /// A request for Claude waiting until Meal Planner is connected to Claude Desktop.
    var claudeRequestAwaitingConnection: String?
    /// ⌘K is open.
    var showsQuickSearch = false
    /// What a screen is asked to show; the screen clears it once it has.
    var request: NavigationRequest?

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
    /// The shopping list in «Напоминания».
    private(set) var reminders: RemindersModel?

    nonisolated static var isDebugBuild: Bool {
        AppIdentity.isDebug(bundleID: Bundle.main.bundleIdentifier ?? "")
    }

    /// Settings → «Основные»: copies go to iCloud Drive instead of the data folder.
    nonisolated static let backupsInICloudKey = "backups.iCloud"

    nonisolated static let iCloudDrive = FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)

    /// Daily copies of the database: in the data folder, or in iCloud Drive when Settings say so and it is there.
    nonisolated static func backups(dataDirectory: URL) -> Backups {
        let iCloud =
            UserDefaults.standard.bool(forKey: backupsInICloudKey)
            && FileManager.default.fileExists(atPath: iCloudDrive.path(percentEncoded: false))
        let folder =
            iCloud
            ? iCloudDrive.appending(path: "Meal Planner/Резервные копии", directoryHint: .isDirectory)
            : dataDirectory.appending(path: "Backups", directoryHint: .isDirectory)
        return Backups(folder: folder)
    }

    var backups: Backups? {
        dataDirectory.map(Self.backups)
    }

    /// The folder Claude Code sessions open in, with instructions on the data.
    var claudeWorkspace: ClaudeWorkspace? {
        dataDirectory.map { ClaudeWorkspace(dataDirectory: $0) }
    }

    /// Writes of the MCP server reach the lists: by its notification, or by the data version when the app
    /// comes back to the front, in case a notification was missed.
    @ObservationIgnored private var externalChanges: ExternalChangesObserver?
    @ObservationIgnored private var activation: NSObjectProtocol?
    private let seenDataVersion = OSAllocatedUnfairLock<Int?>(initialState: nil)

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
                do {
                    try Self.backups(dataDirectory: dataDirectory).backUp(database)
                } catch {
                    Self.log.error("Daily backup failed: \(error, privacy: .public)")
                }
            }
            watchExternalChanges(database)
            reminders = RemindersModel(database: database)
        } catch {
            problem = Problem(title: "Не открылась база данных", message: "\(error)")
        }
    }

    /// Goes where a quick-search hit lives.
    func open(_ hit: QuickSearch.Hit) {
        switch hit.kind {
        case .recipe:
            sidebar = .section(.recipes)
            request = NavigationRequest(section: .recipes, recipe: hit.id)
        case .product:
            sidebar = .section(.products)
            request = NavigationRequest(section: .products, product: hit.id, search: hit.title)
        case .pantry:
            sidebar = .section(.pantry)
            request = NavigationRequest(section: .pantry, search: hit.title)
        case .shopping:
            sidebar = .section(.shopping)
            request = NavigationRequest(section: .shopping, search: hit.title)
        case .category:
            sidebar = .category(hit.id)
        }
    }

    /// Sends the request to Claude, or first offers to connect Meal Planner's server: without it Claude can
    /// neither read nor change the data.
    func askClaude(_ request: String) {
        if ClaudeConnection.current.state() == .connected {
            ClaudeHandoff.send(request, workspace: claudeWorkspace)
        } else {
            claudeRequestAwaitingConnection = request
        }
    }

    private func watchExternalChanges(_ database: AppDatabase) {
        let seen = seenDataVersion
        let refresh: @Sendable () -> Void = {
            Task.detached {
                do {
                    let version = try database.dataVersion()
                    seen.withLock { $0 = version }
                    try database.notifyExternalChanges()
                } catch {
                    Self.log.error("Could not refresh after another process wrote: \(error, privacy: .public)")
                }
            }
        }
        externalChanges = ExternalChangesObserver(refresh)
        seen.withLock { $0 = try? database.dataVersion() }
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { _ in
            Task.detached {
                let version = try? database.dataVersion()
                if seen.withLock({ $0 != version }) {
                    refresh()
                }
            }
        }
    }
}
