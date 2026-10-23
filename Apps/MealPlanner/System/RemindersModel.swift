import AppKit
import EventKit
import MealCore
import MealReminders
import MealStore
import Observation

/// The shopping list in «Напоминания»: settings, access, and a round of sync whenever either side changes — the
/// app's list (Claude's writes included), «Напоминания» (EventKit says so) — and when the app comes back to the
/// front, the Mac wakes up, and every quarter of an hour in case a change slipped by. It runs with the window
/// closed too: the app stays in the menu bar.
@MainActor @Observable
final class RemindersModel {
    static let settingsKey = "reminders.settings"

    var settings: ReminderSettings {
        didSet {
            guard settings != oldValue else { return }
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.settingsKey)
            }
            if settings.isEnabled { schedule() }
        }
    }

    private(set) var lists: [ReminderList] = []
    private(set) var lastSync: Date?
    private(set) var lastReport: SyncReport?
    private(set) var isSyncing = false
    var problem: String?

    let database: AppDatabase
    @ObservationIgnored private var store: EventKitReminderStore?
    @ObservationIgnored private var engine: ShoppingSync?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var periodic: Task<Void, Never>?
    /// Keeps App Nap from putting the rounds off while the app sits in the menu bar.
    @ObservationIgnored private var activity: NSObjectProtocol?

    /// The time between the rounds that only check, in case a change slipped by.
    static let checkInterval: Duration = .seconds(15 * 60)

    init(database: AppDatabase) {
        self.database = database
        settings =
            UserDefaults.standard.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(ReminderSettings.self, from: $0) } ?? ReminderSettings()
        if settings.isEnabled, EventKitReminderStore.isAuthorized, !AppModel.isRunningTests {
            start()
        }
    }

    /// «Синхронизировано с «Напоминаниями» в 10:45», the problem, or that the sync is off.
    var statusLine: String {
        guard settings.isEnabled else { return "Синхронизация с «Напоминаниями» выключена" }
        if let problem { return "«Напоминания»: \(problem)" }
        if settings.listID == nil { return "Выберите список в Настройках → «Напоминания»" }
        guard let lastSync else { return "Синхронизируется с «Напоминаниями»" }
        let time = lastSync.formatted(.dateTime.hour().minute().locale(Formatting.locale))
        return "Синхронизировано с «Напоминаниями» в \(time)"
    }

    var isAuthorized: Bool {
        EventKitReminderStore.isAuthorized
    }

    /// The app's own address in reminders: a Debug build has its own, so the two never take each other's items.
    static var scheme: String {
        AppModel.isDebugBuild ? "mealplanner-debug" : "mealplanner"
    }

    /// Turns the sync on, asking for access to «Напоминания» the first time.
    func enable() async {
        let store = EventKitReminderStore()
        do {
            guard try await store.requestAccess() else {
                problem =
                    "Нет доступа к «Напоминаниям». Разрешите его: Системные настройки → Конфиденциальность и безопасность → Напоминания."
                settings.isEnabled = false
                return
            }
            settings.isEnabled = true
            start()
        } catch {
            problem = "Нет доступа к «Напоминаниям»: \(error.localizedDescription)"
            settings.isEnabled = false
        }
    }

    func disable() {
        settings.isEnabled = false
        stop()
    }

    func createList() {
        guard let store else { return }
        do {
            let list = try store.createList(named: "Покупки")
            refreshLists()
            settings.listID = list.id
        } catch {
            problem = String(describing: error)
        }
    }

    func refreshLists() {
        lists = (try? store?.lists()) ?? []
    }

    /// A round soon: changes come in bursts, a second's quiet gathers them.
    func schedule() {
        guard settings.isEnabled, settings.listID != nil, engine != nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    func syncNow() async {
        guard let engine, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let report = try await engine.sync(settings)
            lastSync = .now
            lastReport = report
            problem = nil
            // Checked off in the shop: into the pantry at once when Settings say not to ask; otherwise the shopping
            // list offers it.
            if !report.checkedElsewhere.isEmpty,
                UserDefaults.standard.bool(forKey: ShoppingScreen.stocksWithoutAskingKey)
            {
                let entries = try database.shoppingEntries(ids: report.checkedElsewhere)
                try database.stockBought(
                    Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.amountInBaseUnit) }), keepOnList: true)
            }
        } catch {
            problem = String(describing: error)
            AppModel.log.error("Reminders sync failed: \(error, privacy: .public)")
        }
    }

    private func start() {
        guard engine == nil else {
            schedule()
            return
        }
        let store = EventKitReminderStore()
        self.store = store
        engine = ShoppingSync(database: database, store: store, scheme: Self.scheme)
        refreshLists()
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: .EKEventStoreChanged, object: store.store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        observers.append(
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        workspaceObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        periodic = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.checkInterval)
                guard !Task.isCancelled else { return }
                self?.schedule()
            }
        }
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Синхронизация покупок с «Напоминаниями»")
        let database = database
        watch = Task { [weak self] in
            do {
                for try await _ in database.observeShopping(ShoppingQuery(), limit: 10_000) {
                    self?.schedule()
                }
            } catch {
                self?.problem = String(describing: error)
            }
        }
        schedule()
    }

    private func stop() {
        pending?.cancel()
        watch?.cancel()
        periodic?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers = []
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        engine = nil
        store = nil
    }
}
