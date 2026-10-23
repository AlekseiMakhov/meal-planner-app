import AppKit
import MealCore
import Testing

@testable import MealPlanner

@MainActor
struct AppStateTests {
    @Test func appIsDarkFromLaunch() {
        #expect(NSApp.appearance?.name == .darkAqua)
    }

    @Test func sidebarListsTheSectionsInOrder() {
        #expect(
            AppModel.Section.allCases.map(\.title) == ["Рецепты", "Меню на неделю", "Запасы", "Покупки", "Продукты"])
    }

    @Test func everySectionHasAnIcon() {
        for section in AppModel.Section.allCases {
            #expect(NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil) != nil, "\(section)")
        }
    }

    @Test func debugBuildOpensItsOwnDatabase() throws {
        let model = AppModel()
        #expect(model.problem == nil)
        #expect(model.database != nil)
        #expect(try #require(model.dataDirectory).lastPathComponent == "inco.mealplanner.debug")
    }

    @Test func theDatabaseStartsWithTheProductBase() throws {
        let database = try #require(AppModel().database)
        #expect(try database.products(ProductQuery(), limit: 1).total > 0)
        #expect(try database.aisles().count == 18)
    }

    @Test func aPersonsLaunchOpensTheWindowTheLoginDoesNot() {
        var opened: [String] = []
        let atLogin = AppModel()
        atLogin.launched(atLogin: true)
        atLogin.windowActionsArrived(open: { opened.append("login") }, settings: {})
        #expect(opened.isEmpty, "at login the app stays in the menu bar")

        let byHand = AppModel()
        byHand.windowActionsArrived(open: { opened.append("person") }, settings: {})
        #expect(opened.isEmpty, "not before the launch is known")
        byHand.launched(atLogin: false)
        byHand.windowActionsArrived(open: { opened.append("again") }, settings: {})
        #expect(opened == ["person"], "once, whichever comes first")
    }

    @Test func onlyTheInstalledCopyTurnsOnLoginByItselfAndOnce() {
        let installed = URL(filePath: "/Applications/MealPlanner.app", directoryHint: .isDirectory)
        let built = URL(filePath: "/Users/me/build/Release/MealPlanner.app", directoryHint: .isDirectory)
        #expect(AppModel.turnsOnLoginItem(bundle: installed, isDebug: false, done: false))
        #expect(!AppModel.turnsOnLoginItem(bundle: installed, isDebug: false, done: true), "the user's choice stands")
        #expect(!AppModel.turnsOnLoginItem(bundle: installed, isDebug: true, done: false))
        #expect(!AppModel.turnsOnLoginItem(bundle: built, isDebug: false, done: false))
    }

    @Test func aReminderLinkOpensTheShoppingList() throws {
        let model = AppModel()
        model.open(try #require(URL(string: "mealplanner-debug://shopping/12")))
        #expect(model.section == .shopping)
    }

    @Test func quickSearchOpensWhereTheHitLives() {
        let model = AppModel()
        model.open(QuickSearch.Hit(kind: .product, id: 5, title: "Фета", detail: ""))
        #expect(model.section == .products)
        #expect(model.request?.product == 5)
        #expect(model.request?.search == "Фета")
        model.open(QuickSearch.Hit(kind: .recipe, id: 7, title: "Омлет", detail: ""))
        #expect(model.section == .recipes)
        #expect(model.request?.recipe == 7)
        model.open(QuickSearch.Hit(kind: .category, id: 3, title: "Супы", detail: ""))
        #expect(model.category == 3)
    }

    @Test func colorTokensComeFromTheAssetCatalog() {
        // A token missing from Assets.xcassets would resolve to nothing; spot-check the ones every screen uses.
        for name in ["Canvas", "TextPrimary", "TextSecondary", "AccentColor", "TagGray", "TagYellow"] {
            #expect(NSColor(named: name, bundle: .main) != nil, "\(name)")
        }
    }
}
