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

    @Test func colorTokensComeFromTheAssetCatalog() {
        // A token missing from Assets.xcassets would resolve to nothing; spot-check the ones every screen uses.
        for name in ["Canvas", "TextPrimary", "TextSecondary", "AccentColor"] {
            #expect(NSColor(named: name, bundle: .main) != nil, "\(name)")
        }
    }
}
