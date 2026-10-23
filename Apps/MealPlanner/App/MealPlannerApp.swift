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
        .defaultWindowPlacement { _, context in
            // Most of the screen, so the week fits with the recipes beside it; a wide display gets a roomy window,
            // not a full one.
            let screen = context.defaultDisplay.visibleRect.size
            let size = CGSize(width: min(screen.width * 0.92, 1500), height: min(screen.height * 0.92, 960))
            return WindowPlacement(.center, size: size)
        }
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Быстрый поиск…") { model.showsQuickSearch = true }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(model.database == nil)
            }
        }

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
