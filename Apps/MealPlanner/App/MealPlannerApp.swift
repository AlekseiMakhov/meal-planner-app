import MealCore
import SwiftUI

@main
struct MealPlannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Opens when a person starts the app; at login Meal Planner stays in the menu bar and syncs.
        Window(AppIdentity.displayName, id: MainWindow.id) {
            MainWindow()
                .environment(delegate.model)
        }
        .defaultWindowPlacement { _, context in
            // Most of the screen, so the week fits with the recipes beside it; a wide display gets a roomy window,
            // not a full one.
            let screen = context.defaultDisplay.visibleRect.size
            let size = CGSize(width: min(screen.width * 0.92, 1500), height: min(screen.height * 0.92, 960))
            return WindowPlacement(.center, size: size)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Быстрый поиск…") { delegate.model.showsQuickSearch = true }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(delegate.model.database == nil)
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(delegate.model)
        } label: {
            MenuBarIcon()
                .environment(delegate.model)
        }

        Settings {
            SettingsView()
                .environment(delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Dark from the first frame: windows, menus, alerts and Settings alike. A light theme comes later,
        // as another set of values for the same color tokens.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Set before launching finishes, so a link that started the app — the one in a reminder — is not lost.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReply:)), forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppModel.isRunningTests else { return }
        model.launched(atLogin: Self.isLoginLaunch)
    }

    /// Starting the app again from Finder or Spotlight while it sits in the menu bar shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            model.showMainWindow()
        }
        return true
    }

    /// Closing the window leaves Meal Planner in the menu bar, syncing; ⌘Q or «Выйти» quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Started by the login item rather than by a person: the launch event says so.
    private static var isLoginLaunch: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication else {
            return false
        }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: text)
        else { return }
        model.open(url)
    }
}
