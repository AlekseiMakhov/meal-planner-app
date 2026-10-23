import Observation
import ServiceManagement
import os

/// Opening Meal Planner at login, through `SMAppService.mainApp`. The system keeps the setting; the user may also
/// change it in System Settings → General → Login Items.
@MainActor @Observable
final class LoginItem {
    enum State {
        case enabled
        case disabled
        /// Registered, but the user has to allow it in System Settings.
        case needsApproval
    }

    private static let log = Logger(subsystem: "inco.mealplanner", category: "login-item")

    private(set) var state = LoginItem.read()

    /// Reads the state again: it may change in System Settings while the app runs.
    func refresh() {
        state = Self.read()
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.log.error("Changing the login item failed: \(error, privacy: .public)")
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func read() -> State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .needsApproval
        default: .disabled
        }
    }
}
