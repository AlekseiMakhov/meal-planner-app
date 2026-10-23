import AppKit
import MealCore
import MealStore
import OSLog
import Observation
import os

/// What the window shows and the data it works with. The app outlives its window: it stays in the menu bar and
/// keeps the shopping list in sync, so the window is opened and closed through this model.
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
    /// Under tests the app neither syncs, nor tidies its data, nor opens its window.
    nonisolated static let isRunningTests = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("XCTest") }

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
    /// What is still to buy: the sidebar's badge and the menu bar's menu.
    private(set) var shoppingCount = 0
    /// Opening Meal Planner at login, without its window.
    let loginItem = LoginItem()
    private(set) var isWindowOpen = false

    /// The window and Settings open through actions the menu bar icon hands over: it is the one view that always
    /// exists, with or without a window.
    @ObservationIgnored private var openWindow: (@MainActor () -> Void)?
    @ObservationIgnored private var openSettings: (@MainActor () -> Void)?
    /// A person started the app, not the login: the window opens as soon as it can.
    @ObservationIgnored private var opensWindowAtLaunch = false

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
            if !Self.isRunningTests {
                maintainDaily(database, dataDirectory)
            }
            watchExternalChanges(database)
            watchShoppingCount(database)
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

    /// `mealplanner://shopping/…` — the link in a reminder — opens the shopping list; any other link, the window.
    func open(_ url: URL) {
        showMainWindow(url.host() == "shopping" ? .shopping : nil)
    }

    // MARK: - The window

    /// The app has started: started by a person, it opens its window; at login it stays in the menu bar.
    func launched(atLogin: Bool) {
        opensWindowAtLaunch = !atLogin
        openWindowAtLaunch()
        let defaults = UserDefaults.standard
        if Self.turnsOnLoginItem(
            bundle: Bundle.main.bundleURL, isDebug: Self.isDebugBuild,
            done: defaults.bool(forKey: Self.loginItemDoneKey))
        {
            defaults.set(true, forKey: Self.loginItemDoneKey)
            loginItem.set(true)
        }
    }

    /// Set once the installed copy has turned on opening at login by itself.
    nonisolated static let loginItemDoneKey = "loginItem.turnedOnOnce"

    /// The copy in /Applications runs as a service: on its first run it turns on opening at login, once. After
    /// that the choice in Settings stands. A Debug build lives in DerivedData and never does.
    nonisolated static func turnsOnLoginItem(bundle: URL, isDebug: Bool, done: Bool) -> Bool {
        !done && !isDebug && bundle.path(percentEncoded: false).hasPrefix("/Applications/")
    }

    /// The menu bar icon hands over the actions that open windows.
    func windowActionsArrived(open: @escaping @MainActor () -> Void, settings: @escaping @MainActor () -> Void) {
        openWindow = open
        openSettings = settings
        openWindowAtLaunch()
    }

    /// The launch and the icon come in either order; the window opens once both are there.
    private func openWindowAtLaunch() {
        guard opensWindowAtLaunch, openWindow != nil else { return }
        opensWindowAtLaunch = false
        showMainWindow()
    }

    func showMainWindow(_ section: Section? = nil) {
        if let section {
            sidebar = .section(section)
        }
        NSApp.activate()
        openWindow?()
    }

    func showSettings() {
        NSApp.activate()
        openSettings?()
    }

    /// In the Dock and the app switcher while the window is open; only in the menu bar without it.
    func windowDidOpen() {
        isWindowOpen = true
        setActivationPolicy(.regular)
    }

    func windowDidClose() {
        isWindowOpen = false
        setActivationPolicy(.accessory)
    }

    private func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular {
            NSApp.activate()
        }
    }

    // MARK: - Claude

    /// Sends the request to Claude, or first offers to connect Meal Planner's server: without it Claude can
    /// neither read nor change the data.
    func askClaude(_ request: String) {
        if ClaudeConnection.current.state() == .connected {
            ClaudeHandoff.send(request, workspace: claudeWorkspace)
        } else {
            claudeRequestAwaitingConnection = request
        }
    }

    // MARK: - In the background

    /// Once a day — also when the app has been running in the menu bar for days: the copy, the trash, photos
    /// left behind. The window does not wait for it.
    private func maintainDaily(_ database: AppDatabase, _ dataDirectory: URL) {
        Task.detached(priority: .background) {
            var done: Day?
            while !Task.isCancelled {
                let today = Day.today()
                if done != today {
                    done = today
                    _ = try? database.emptyTrash()
                    _ = try? database.removeUnusedImages()
                    do {
                        try Self.backups(dataDirectory: dataDirectory).backUp(database)
                    } catch {
                        Self.log.error("Daily backup failed: \(error, privacy: .public)")
                    }
                }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    private func watchShoppingCount(_ database: AppDatabase) {
        Task { [weak self] in
            do {
                for try await count in database.observeShoppingCount() { self?.shoppingCount = count }
            } catch {
                Self.log.error("The shopping count stopped: \(error, privacy: .public)")
            }
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
