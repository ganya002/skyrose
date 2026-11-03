import Foundation
import ServiceManagement

/// Start-at-login for the WM agent via `SMAppService.mainApp` (spec 9: no LaunchDaemons, no root).
/// Only works from the signed app bundle; from `swift run` the status is `.notFound`.
public enum LoginItem {
    public enum State: String, Sendable {
        case enabled, disabled, requiresApproval, notFound
    }

    public static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    /// Registers or unregisters the app as a login item. The user may still have to approve it
    /// in System Settings › General › Login Items (`state == .requiresApproval`).
    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
