import MealCore
import SwiftUI

@main
struct MealPlannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window(AppIdentity.displayName, id: MainWindow.id) {
            MainWindow()
                .environment(model)
        }
        .defaultSize(width: 1200, height: 780)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Dark from the first frame: windows, menus, alerts and Settings alike. A light theme comes later,
        // as another set of values for the same color tokens.
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}
