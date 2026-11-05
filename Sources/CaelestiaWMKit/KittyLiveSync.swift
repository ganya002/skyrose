import AppKit
import CaelestiaCore
import Foundation

/// Keeps kitty's colours on the SkyRose scheme: on every scheme change (and at start) the theme
/// include is rewritten, and running kittys reload their config (`SIGUSR1`, kitty's documented
/// reload signal). Only when the user's kitty.conf includes the SkyRose profile (Settings ›
/// Terminal › Set up kitty, or `skyrose kitty install`): otherwise nothing is written or signalled.
@MainActor
enum KittyLiveSync {
    private static let queue = DispatchQueue(label: "com.skyrose.mac.kitty-sync", qos: .utility)

    static func apply(_ scheme: Scheme) {
        queue.async {
            do {
                guard try KittySetup().syncTheme(scheme: scheme) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { reloadRunningKittys() } }
            } catch {
                Log.wm.error("kitty theme: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func reloadRunningKittys() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: TerminalChoice.kittyBundleID)
        for app in apps where app.processIdentifier > 0 { kill(app.processIdentifier, SIGUSR1) }
        if !apps.isEmpty { Log.wm.notice("kitty theme updated; reloaded \(apps.count) kitty instance(s)") }
    }
}
