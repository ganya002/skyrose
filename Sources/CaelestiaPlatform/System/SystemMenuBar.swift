import Foundation
import CaelestiaCore

/// Applies the Appearance menu-bar choice and can show the bar for a few seconds.
///
/// The choice is stored in Application Support so the window manager and Settings agree.
/// `_HIHideMenuBar` is journaled first, so Undo and the uninstaller put the old value back.
@MainActor
public enum SystemMenuBar {
    public static let peekSeconds: TimeInterval = 5
    private static var peekToken = 0

    public static func current(directory: URL = Paths.appSupport) -> MenuBarChoice {
        MenuBarChoiceStore.read(MenuBarChoiceStore.file(in: directory)) ?? .shown
    }

    /// Writes the choice and the hide flag. Does not restart the Mac.
    public static func apply(_ choice: MenuBarChoice, tweaks: SystemTweaks = SystemTweaks(), directory: URL = Paths.appSupport) throws {
        let hide = MenuBarPlan.hides(choice)
        if tweaks.isOn(.menuBarAutoHide) != hide {
            try tweaks.backup.write(hide, domain: SystemTweaks.globalDomain, key: "_HIHideMenuBar", note: "menu bar \(choice.rawValue)")
            SystemTweaks.activateLive(.menuBarAutoHide, hide)
        }
        try MenuBarChoiceStore.write(choice, to: MenuBarChoiceStore.file(in: directory))
    }

    /// Shows the bar, then puts the saved choice back. A second peek restarts the wait.
    public static func peek(tweaks: SystemTweaks = SystemTweaks(), directory: URL = Paths.appSupport) {
        let choice = current(directory: directory)
        peekToken += 1
        let token = peekToken
        if tweaks.isOn(.menuBarAutoHide) {
            try? tweaks.backup.write(false, domain: SystemTweaks.globalDomain, key: "_HIHideMenuBar", note: "menu bar peek")
            SystemTweaks.activateLive(.menuBarAutoHide, false)
        }
        guard choice != .shown else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + peekSeconds) {
            guard token == peekToken else { return }
            try? apply(choice, tweaks: tweaks, directory: directory)
        }
    }
}
