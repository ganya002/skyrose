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
    private static var peekPending = false
    private static let hideKey = "_HIHideMenuBar"

    /// The saved choice, unless macOS disagrees (the user changed System Settings, or no choice
    /// was ever saved). macOS decides whether the bar hides, so the setting has to say that too.
    public static func current(tweaks: SystemTweaks = SystemTweaks(), directory: URL = Paths.appSupport) -> MenuBarChoice {
        let hidden = tweaks.isOn(.menuBarAutoHide)
        let saved = MenuBarChoiceStore.read(MenuBarChoiceStore.file(in: directory))
        if let saved, MenuBarPlan.hides(saved) == hidden { return saved }
        return hidden ? .auto : .shown
    }

    /// Writes the choice and the hide flag. Does not restart the Mac.
    public static func apply(_ choice: MenuBarChoice, tweaks: SystemTweaks = SystemTweaks(), directory: URL = Paths.appSupport) throws {
        // A choice made during a peek replaces whatever the peek meant to put back.
        peekToken += 1
        peekPending = false
        let hide = MenuBarPlan.hides(choice)
        if tweaks.isOn(.menuBarAutoHide) != hide {
            try tweaks.backup.write(hide, domain: SystemTweaks.globalDomain, key: hideKey, note: "menu bar \(choice.rawValue)")
        }
        try MenuBarChoiceStore.write(choice, to: MenuBarChoiceStore.file(in: directory))
        // Last, and every time: Auto-hide to Off leaves the flag alone but changes the layout,
        // and the window manager reads the choice file when this arrives.
        tweaks.activate(.menuBarAutoHide, hide)
    }

    /// Shows a hidden bar, then hides it again. A second peek restarts the wait.
    public static func peek(tweaks: SystemTweaks = SystemTweaks(), seconds: TimeInterval = peekSeconds) {
        MenuBarOverride.peek(seconds: seconds)
        let hidden = tweaks.isOn(.menuBarAutoHide)
        guard hidden || peekPending else { return }
        if hidden {
            try? tweaks.backup.write(false, domain: SystemTweaks.globalDomain, key: hideKey, note: "menu bar peek")
            tweaks.activate(.menuBarAutoHide, false)
        }
        peekPending = true
        peekToken += 1
        let token = peekToken
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard token == peekToken else { return }
            peekPending = false
            try? tweaks.backup.write(true, domain: SystemTweaks.globalDomain, key: hideKey, note: "menu bar peek ended")
            tweaks.activate(.menuBarAutoHide, true)
        }
    }
}
