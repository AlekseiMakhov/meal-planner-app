import Foundation
import MealCore
import MealStore
import Testing

@testable import MealReminders

/// «Напоминания» in memory: what a family's iPhones would do to the list, done by the test.
@MainActor
final class FakeReminderStore: ReminderStore {
    var reminders: [String: ReminderItem] = [:]
    var order: [String] = []
    private var next = 1

    func lists() throws -> [ReminderList] {
        [ReminderList(id: "shopping", title: "Покупки", account: "iCloud")]
    }

    func createList(named name: String) throws -> ReminderList {
        ReminderList(id: "new", title: name, account: "iCloud")
    }

    func reminders(in listID: String) async throws -> [ReminderItem] {
        order.compactMap { reminders[$0] }
    }

    func create(_ reminder: ReminderItem, in listID: String) throws -> String {
        var reminder = reminder
        reminder.id = "r\(next)"
        next += 1
        reminders[reminder.id] = reminder
        order.append(reminder.id)
        return reminder.id
    }

    func update(_ reminder: ReminderItem) throws {
        guard reminders[reminder.id] != nil else { return }
        reminders[reminder.id] = reminder
    }

    func delete(id: String) throws {
        reminders[id] = nil
        order.removeAll { $0 == id }
    }

    /// Added on a phone: no address of the app's.
    func addFromPhone(_ title: String) {
        _ = try? create(ReminderItem(title: title), in: "shopping")
    }

    func titles() -> [String] {
        order.compactMap { reminders[$0]?.title }
    }

    func reminder(titled title: String) -> ReminderItem? {
        reminders.values.first { $0.title == title }
    }
}

@MainActor
struct ShoppingSyncTests {
    private let database: AppDatabase
    private let store = FakeReminderStore()
    private let sync: ShoppingSync
    private var settings = ReminderSettings()
    private let thursday = Day(year: 2026, month: 10, day: 22)

    init() throws {
        database = try AppDatabase.inMemory(seeded: true)
        sync = ShoppingSync(database: database, store: store, scheme: "mealplanner")
        settings.isEnabled = true
        settings.listID = "shopping"
    }

    private func product(_ name: String) throws -> Product {
        guard case .found(let product) = try database.matchProduct(named: name) else { throw StoreError("нет \(name)") }
        return product
    }

    private func names() throws -> [String] {
        try database.allShoppingEntries().map { ShoppingRowTitle.of($0) }
    }

    @Test func theAppsListReachesRemindersWithAmountsAndDishes() async throws {
        var settings = self.settings
        let milk = try product("молоко")
        try database.addToShopping([
            ShoppingAddition(
                product: milk.id, amount: 1, unit: .liter,
                reason: ShoppingReason(recipeID: 1, title: "Блины", day: "2026-10-24")),
            ShoppingAddition(text: "Батарейки", amount: 4),
        ])
        let bought = try database.addToShopping([ShoppingAddition(text: "Свечи")])
        try database.setChecked(true, items: Set(bought))
        settings.notesDays = true
        settings.shoppingWeekday = 6

        let report = try await sync.sync(settings, today: thursday)
        #expect(report.created == 2)
        #expect(Set(store.titles()) == ["Молоко 3,2% — 1 л", "Батарейки — 4 шт."])
        let milkReminder = try #require(store.reminder(titled: "Молоко 3,2% — 1 л"))
        #expect(milkReminder.notes == "для: Блины (СБ)")
        #expect(milkReminder.url?.absoluteString.hasPrefix("mealplanner://shopping/") == true)
        #expect(milkReminder.dueDay == Day(year: 2026, month: 10, day: 24))

        // A second round with nothing changed changes nothing.
        let again = try await sync.sync(settings, today: thursday)
        #expect(!again.changedReminders && !again.changedApp)
    }

    @Test func checkingOffOnAPhoneMarksTheItemBought() async throws {
        let ids = try database.addToShopping([ShoppingAddition(text: "Хлеб"), ShoppingAddition(text: "Сыр")])
        try await sync.sync(settings)
        var bread = try #require(store.reminder(titled: "Хлеб"))
        bread.isCompleted = true
        try store.update(bread)

        let report = try await sync.sync(settings)
        #expect(report.checkedElsewhere == [ids[0]])
        #expect(try database.shoppingEntries(ids: [ids[0]]).first?.item.isChecked == true)

        // Checked in the app: the reminder follows.
        try database.setChecked(true, items: [ids[1]])
        try await sync.sync(settings)
        #expect(store.reminder(titled: "Сыр")?.isCompleted == true)

        // Unchecked on the phone again.
        bread.isCompleted = false
        try store.update(bread)
        let back = try await sync.sync(settings)
        #expect(back.uncheckedElsewhere == 1)
        #expect(try database.shoppingEntries(ids: [ids[0]]).first?.item.isChecked == false)
    }

    @Test func deletionsTravelBothWays() async throws {
        let ids = try database.addToShopping([ShoppingAddition(text: "Хлеб"), ShoppingAddition(text: "Соль крупная")])
        try await sync.sync(settings)
        try store.delete(id: try #require(store.reminder(titled: "Хлеб")).id)
        try database.removeShoppingItems([ids[1]])

        let report = try await sync.sync(settings)
        #expect(report.removedElsewhere == 1)
        #expect(report.deleted == 1)
        #expect(try database.allShoppingEntries().isEmpty)
        #expect(store.reminders.isEmpty)
    }

    @Test func boughtAndClearedItemsLeaveRemindersToo() async throws {
        let ids = try database.addToShopping([ShoppingAddition(text: "Хлеб")])
        try await sync.sync(settings)
        try database.setChecked(true, items: Set(ids))
        try await sync.sync(settings)
        try database.clearChecked()
        // Even if iCloud dropped the app's address from the reminder, it is known as the app's own.
        var reminder = try #require(store.reminders.values.first)
        reminder.url = nil
        try store.update(reminder)
        try await sync.sync(settings)
        #expect(store.reminders.isEmpty)
        #expect(try database.allShoppingEntries().isEmpty)
    }

    @Test func whatTheFamilyAddsComesIn() async throws {
        let milk = try product("молоко")
        try database.addToShopping([ShoppingAddition(product: milk.id, amount: 1, unit: .liter)])
        try await sync.sync(settings)
        store.addFromPhone("хлеб бородинский")
        store.addFromPhone("2 л молока")
        store.addFromPhone("🔋 Батарейки AA")

        let report = try await sync.sync(settings)
        #expect(report.imported == 3)
        #expect(Set(try names()) == ["Молоко 3,2% — 3 л", "Хлеб бородинский", "Батарейки AA"])
        // The milk had a reminder of its own: the family's one goes, and the next round says three litres.
        try await sync.sync(settings)
        #expect(Set(store.titles()) == ["Молоко 3,2% — 3 л", "Хлеб бородинский", "Батарейки AA"])
        #expect(store.reminders.count == 3)
        #expect(try await sync.sync(settings).changedApp == false)
    }

    @Test func familyItemsStayOutWhenNotWanted() async throws {
        var settings = self.settings
        settings.acceptsFamilyItems = false
        store.addFromPhone("хлеб")
        try await sync.sync(settings)
        #expect(try database.allShoppingEntries().isEmpty)
        #expect(store.reminders.count == 1)
    }

    @Test func anAmountTypedOnAPhoneChangesTheItem() async throws {
        let milk = try product("молоко")
        let ids = try database.addToShopping([ShoppingAddition(product: milk.id, amount: 1, unit: .liter)])
        try await sync.sync(settings)
        var reminder = try #require(store.reminders.values.first)
        reminder.title = "Молоко — 2 л"
        try store.update(reminder)
        try await sync.sync(settings)
        let item = try #require(try database.shoppingEntries(ids: ids).first?.item)
        #expect(item.amount == 2)
        #expect(item.unit == .liter)
        #expect(store.titles() == ["Молоко 3,2% — 2 л"])
    }

    @Test func boughtItemsLeaveAfterTheDaysSet() async throws {
        var settings = self.settings
        let ids = try database.addToShopping([ShoppingAddition(text: "Хлеб"), ShoppingAddition(text: "Сыр")])
        try database.setChecked(true, items: [ids[0]])
        settings.clearBoughtAfterDays = 2
        try await sync.sync(settings, now: Date.now.addingTimeInterval(3 * 86_400))
        #expect(try names() == ["Сыр"])
    }

    @Test func titlesCanLeaveTheAmountToTheNoteAndCarryTheAislesEmoji() throws {
        let milk = try product("молоко")
        let entry = ShoppingEntry(
            item: ShoppingItem(id: 1, productID: milk.id, amount: 1500, unit: .milliliter), product: milk)
        var settings = ReminderSettings()
        settings.aisleEmoji = true
        #expect(ReminderText.title(entry, settings: settings, aisle: "Молочное и яйца") == "🥛 Молоко 3,2% — 1,5 л")
        settings.titleStyle = .nameOnly
        #expect(ReminderText.title(entry, settings: settings, aisle: "Прочее") == "🛒 Молоко 3,2%")
        #expect(ReminderText.notes(entry, settings: settings) == "1,5 л")
        #expect(ReminderText.plain("🥛 Молоко — 1 л") == "Молоко — 1 л")
        settings.shoppingWeekday = 4
        #expect(settings.dueDay(from: thursday) == thursday)
        settings.shoppingWeekday = 1
        #expect(settings.dueDay(from: thursday) == Day(year: 2026, month: 10, day: 26))
    }
}

/// How the tests name a shopping line: «Молоко 3,2% — 3 л».
enum ShoppingRowTitle {
    static func of(_ entry: ShoppingEntry) -> String {
        guard let amount = entry.item.amount else { return entry.name }
        return entry.name + " — " + AmountText.quantity(amount, entry.item.unit ?? .piece)
    }
}
