import AppKit
import CaelestiaCore
import Foundation

/// Runs the `app.*` and `exec` keybind actions: ⌥ + T opens the terminal chosen in Settings ›
/// Terminal (`apps.terminal`, see ``TerminalChoice``), and the browser / editor / file manager /
/// audio settings from `[apps]`. Everything is started with `/usr/bin/open` or `/bin/sh -c` as
/// the user, detached from the WM.
@MainActor
public enum AppLauncher {
    /// What an action will run: the executable and its arguments. Pure, for tests.
    public static func plan(for action: Action, apps: AppsConfig) -> (executable: String, arguments: [String])? {
        func open(_ target: String) -> (String, [String]) {
            if let url = URL(string: target), url.scheme != nil, !TerminalChoice.looksLikeBundleID(target) {
                return ("/usr/bin/open", [url.absoluteString])
            }
            return TerminalChoice.looksLikeBundleID(target) ? ("/usr/bin/open", ["-b", target]) : ("/usr/bin/open", ["-a", target])
        }
        switch action.kind {
        case .appTerminal:
            let choice = TerminalChoice(config: apps.terminal)
            if let args = choice.openArguments { return ("/usr/bin/open", args) }
            return ("/bin/sh", ["-c", choice.configValue])
        case .appBrowser: return open(apps.browser)
        case .appEditor: return open(apps.editor)
        case .appFiles: return open(apps.fileManager)
        case .appAudioSettings: return open(apps.audioSettings)
        case .exec:
            guard case .string(let cmd)? = action.args["cmd"], !cmd.isEmpty else { return nil }
            return ("/bin/sh", ["-c", cmd])
        default: return nil
        }
    }

    /// Runs `action` when it is one of ours. True when it was handled.
    @discardableResult
    public static func handle(_ action: Action, apps: AppsConfig) -> Bool {
        guard let (exe, args) = plan(for: action, apps: apps) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            Log.wm.info("launched \(action.kind.rawValue, privacy: .public)")
        } catch {
            Log.wm.error("\(action.kind.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        return true
    }
}

/// Finds and opens SkyRose Settings (the onboarding lives there).
@MainActor
public enum SettingsLauncher {
    public static let bundleID = "com.skyrose.mac.settings"
    /// Posted (distributed) when Settings is already running: `userInfo["arguments"]` carries the
    /// same arguments a fresh launch would get.
    public static let showNotification = Notification.Name("com.skyrose.mac.settings.show")

    /// Next to SkyRose.app (dist/ or ~/Applications), else wherever Launch Services knows it.
    public static var appURL: URL? {
        let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("SkyRose Settings.app")
        if FileManager.default.fileExists(atPath: sibling.path) { return sibling }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Opens Settings with `arguments` (e.g. an ``OnboardingRequest``). False when Settings is
    /// not installed.
    @discardableResult
    public static func open(arguments: [String]) -> Bool {
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first != nil {
            DistributedNotificationCenter.default().postNotificationName(
                showNotification, object: nil, userInfo: ["arguments": arguments], deliverImmediately: true)
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
            return true
        }
        guard let url = appURL else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = arguments
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { Log.wm.error("cannot open SkyRose Settings: \(error.localizedDescription, privacy: .public)") }
        }
        return true
    }

    @discardableResult
    public static func open(_ request: OnboardingRequest) -> Bool { open(arguments: request.arguments) }
}
