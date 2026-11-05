import AppKit
import CaelestiaCore
import CaelestiaPlatform
import Foundation

/// Keeps `appearance.cursor` applied for this login session: on start, on config change, after
/// wake / display changes and every 15 s (macOS can drop registered cursors), and puts the macOS
/// cursors back when the option is cleared and when the WM quits (panic and uninstall included).
@MainActor
public final class CursorController {
    public let manager: CursorThemeManager
    public let library: CursorCapeLibrary
    private(set) var desired: String = ""
    private var cape: CursorCape?
    private(set) var applied = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    public private(set) var lastReport: CursorThemeManager.Report?
    public private(set) var lastError: String?

    public init(manager: CursorThemeManager = CursorThemeManager(), library: CursorCapeLibrary = CursorCapeLibrary()) {
        self.manager = manager
        self.library = library
    }

    public func start(identifier: String) {
        update(identifier: identifier)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.ensureApplied() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.ensureApplied() } })
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.ensureApplied() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// `appearance.cursor` changed (or the WM started).
    public func update(identifier raw: String) {
        let identifier = raw.trimmingCharacters(in: .whitespaces)
        guard identifier != desired || (!identifier.isEmpty && !applied) else { return }
        desired = identifier
        if identifier.isEmpty {
            resetIfNeeded()
            return
        }
        do {
            let cape = try library.load(identifier)
            self.cape = cape
            let report = try manager.apply(cape)
            lastReport = report
            lastError = report.failed.isEmpty ? nil : "not applied: \(report.failed.joined(separator: ", "))"
            applied = !report.applied.isEmpty
            Log.wm.notice("cursor \(identifier, privacy: .public): \(report.applied.count) applied, \(report.failed.count) failed, wait cursor left to macOS")
        } catch {
            cape = nil
            applied = false
            lastError = "cape \"\(identifier)\" not found or unreadable"
            Log.wm.error("cursor \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-applies when macOS dropped the cursors (wake, display change, other apps).
    public func ensureApplied() {
        guard !desired.isEmpty, let cape, !manager.isApplied(cape) else { return }
        Log.wm.notice("cursor theme was dropped by the system; re-applying")
        if let report = try? manager.apply(cape) { lastReport = report; applied = !report.applied.isEmpty }
    }

    /// Puts the macOS cursors back if SkyRose changed them this boot.
    public func resetIfNeeded() {
        cape = nil
        guard applied || manager.backup.exists else { return }
        let report = manager.reset()
        applied = false
        if report.ok {
            Log.wm.notice("cursors reset to macOS (\(report.restored.count) restored)")
        } else {
            lastError = "could not restore: \(report.failed.joined(separator: ", "))"
            Log.wm.error("cursor reset incomplete: \(report.failed.joined(separator: ", "), privacy: .public)")
        }
    }

    /// WM quit: stop watching and put the macOS cursors back.
    public func stop() {
        timer?.invalidate()
        timer = nil
        for o in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            NotificationCenter.default.removeObserver(o)
        }
        observers = []
        desired = ""
        resetIfNeeded()
    }

    public var status: [String: String] {
        [
            "cursor": desired.isEmpty ? "macOS" : desired,
            "applied": applied ? "yes" : "no",
            "error": lastError ?? "",
            "waitCursor": "macOS (never replaced)",
        ]
    }
}
