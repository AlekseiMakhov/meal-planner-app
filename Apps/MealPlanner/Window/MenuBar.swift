import AppKit
import MealCore
import SwiftUI

/// The icon in the menu bar. It always exists, window or not, so it hands the window actions to the model.
struct MenuBarIcon: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: model.reminders?.problem == nil ? "fork.knife" : "exclamationmark.triangle")
            .accessibilityLabel(AppIdentity.displayName)
            .task {
                model.windowActionsArrived(open: { openWindow(id: MainWindow.id) }, settings: { openSettings() })
            }
    }
}

/// The menu under the icon: how the sync with «Напоминания» stands, what is left to buy, and the way back to the
/// window.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if AppModel.isDebugBuild {
            Text("Debug-сборка, свои данные")
        }
        if let reminders = model.reminders {
            Text(reminders.statusLine)
            if reminders.settings.isEnabled, reminders.settings.listID != nil {
                Button("Синхронизировать сейчас") {
                    Task { await reminders.syncNow() }
                }
                .disabled(reminders.isSyncing)
            }
        }
        Divider()
        Button("Открыть Meal Planner") { model.showMainWindow() }
            .keyboardShortcut("o")
        Button(
            model.shoppingCount == 0
                ? "Покупки"
                : "Покупки — \(Formatting.count(model.shoppingCount, "позиция", "позиции", "позиций"))"
        ) {
            model.showMainWindow(.shopping)
        }
        Button("Настройки…") { model.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Выйти из Meal Planner") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
