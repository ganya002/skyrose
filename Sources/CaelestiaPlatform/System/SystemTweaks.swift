import AppKit
import CaelestiaCore
import Foundation

/// The recommended macOS tweaks the onboarding offers: Dock and menu bar hide automatically, so
/// the SkyRose bar and frame have the screen edges to themselves.
///
/// Nothing happens until the user clicks Apply. Every write goes through ``DefaultsBackup``: the
/// value from before is recorded in the restore manifest first, so Undo (and the future
/// uninstaller) puts back exactly what was there, including "the key did not exist".
public struct SystemTweak: Identifiable, Equatable, Sendable {
    public enum ID: String, Sendable, CaseIterable {
        case dockAutoHide
        case menuBarAutoHide
    }

    public var id: ID
    public var title: String
    /// What changes, in plain words.
    public var change: String
    public var domain: String
    public var key: String
    /// The value SkyRose recommends.
    public var recommended: Bool

    public static let dockAutoHide = SystemTweak(
        id: .dockAutoHide, title: "Hide the Dock automatically",
        change: "The Dock slides away and comes back when you move the pointer to the bottom of the screen.",
        domain: "com.apple.dock", key: "autohide", recommended: true)

    public static let menuBarAutoHide = SystemTweak(
        id: .menuBarAutoHide, title: "Hide the menu bar automatically",
        change: "The menu bar slides away and comes back when you move the pointer to the top of the screen.",
        domain: SystemTweaks.globalDomain, key: "_HIHideMenuBar", recommended: true)

    public static let all: [SystemTweak] = [.dockAutoHide, .menuBarAutoHide]
}

/// Hides the Dock so completely that the pointer cannot bring it back, without unloading it.
/// The Dock process also runs Mission Control and Spaces, so it is restarted, never disabled.
/// Every original value is journaled before it is changed, including keys that did not exist.
public final class DockRemoval {
    public static let domain = "com.apple.dock"
    public static let delayKey = "autohide-delay"
    public static let modifierKey = "autohide-time-modifier"
    public static let tileKey = "tilesize"
    /// Long enough that the Dock's show animation never starts when the pointer hits the edge.
    public static let hiddenDelay = 1000.0
    public static let hiddenTileSize = 16

    public let backup: DefaultsBackup
    /// `killall Dock`: the process relaunches itself. Tests pass a no-op.
    public var restart: () -> Void

    public init(backup: DefaultsBackup = DefaultsBackup(journal: BackupJournal(url: Paths.restoreManifest)),
                restart: @escaping () -> Void = DockRemoval.restartLive) {
        self.backup = backup
        self.restart = restart
    }

    public static func restartLive() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Dock"]
        try? p.run()
    }

    /// True when SkyRose's "never show" values are what macOS has now.
    public func isHidden() -> Bool {
        let hide = (backup.store.value(domain: Self.domain, key: "autohide") as? NSNumber)?.boolValue ?? false
        let delay = (backup.store.value(domain: Self.domain, key: Self.delayKey) as? NSNumber)?.doubleValue ?? 0
        return hide && delay >= Self.hiddenDelay - 0.001
    }

    /// Writes the hidden values. A key already at the target is left alone (and not re-journaled).
    public func hide() throws {
        var changed = false
        changed = try set(true, key: "autohide") || changed
        changed = try set(Self.hiddenDelay, key: Self.delayKey) || changed
        changed = try set(0.0, key: Self.modifierKey) || changed
        changed = try set(Self.hiddenTileSize, key: Self.tileKey) || changed
        if changed { restart() }
    }

    /// Puts back the first journaled value of each key (or leaves a key SkyRose never wrote).
    public func show() throws {
        var changed = false
        for key in ["autohide", Self.delayKey, Self.modifierKey, Self.tileKey] {
            guard let first = try backup.journal.firstEntry(domain: Self.domain, key: key) else { continue }
            let now = BackupValue(plist: backup.store.value(domain: Self.domain, key: key))
            if now == first.oldValue { continue }
            try backup.write(first.oldValue.plistValue, domain: Self.domain, key: key, note: "dock shown again")
            changed = true
        }
        if changed { restart() }
    }

    @discardableResult
    private func set(_ value: Any, key: String) throws -> Bool {
        let now = BackupValue(plist: backup.store.value(domain: Self.domain, key: key))
        if now == BackupValue(plist: value) { return false }
        try backup.write(value, domain: Self.domain, key: key, note: "remove the Dock")
        return true
    }
}

/// Reads, applies and undoes ``SystemTweak``s.
public final class SystemTweaks {
    /// `NSGlobalDomain` (what `defaults write -g` uses); mapped to `kCFPreferencesAnyApplication`.
    public static let globalDomain = "NSGlobalDomain"

    public let backup: DefaultsBackup
    /// Makes a written value take effect now (Dock: CoreDock call or a Dock restart; menu bar: a
    /// distributed notification). Tests pass a no-op.
    let activate: (SystemTweak.ID, Bool) -> Void

    public init(backup: DefaultsBackup = DefaultsBackup(journal: BackupJournal(url: Paths.restoreManifest)),
                activate: @escaping (SystemTweak.ID, Bool) -> Void = SystemTweaks.activateLive) {
        self.backup = backup
        self.activate = activate
    }

    /// The current value (absent counts as off: that is the macOS default for both).
    public func isOn(_ t: SystemTweak) -> Bool {
        (backup.store.value(domain: t.domain, key: t.key) as? NSNumber)?.boolValue ?? false
    }

    /// True when SkyRose changed this setting and has not put it back.
    public func isChangedBySkyRose(_ t: SystemTweak) -> Bool {
        guard let first = try? backup.journal.firstEntry(domain: t.domain, key: t.key) else { return false }
        return BackupValue(plist: backup.store.value(domain: t.domain, key: t.key)) != first.oldValue
    }

    /// Applies the recommended value (records the old one first). Already on: nothing is written.
    public func apply(_ t: SystemTweak) throws {
        guard isOn(t) != t.recommended else { return }
        try backup.write(t.recommended, domain: t.domain, key: t.key, note: "onboarding: \(t.title)")
        activate(t.id, t.recommended)
    }

    /// Puts back the value from before SkyRose's first change (also recorded, so the manifest
    /// shows the full history). Nothing recorded: nothing to undo.
    public func undo(_ t: SystemTweak) throws {
        guard let first = try backup.journal.firstEntry(domain: t.domain, key: t.key) else { return }
        try backup.write(first.oldValue.plistValue, domain: t.domain, key: t.key, note: "undo: \(t.title)")
        activate(t.id, (first.oldValue.plistValue as? NSNumber)?.boolValue ?? false)
    }

    /// Live activation used by the app.
    public static func activateLive(_ id: SystemTweak.ID, _ on: Bool) {
        switch id {
        case .dockAutoHide:
            // CoreDock applies it without restarting the Dock; without the symbol, the Dock
            // re-reads its preferences when it restarts (it relaunches by itself at once).
            if let fn = coreDockSetAutoHide { fn(on) } else {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                p.arguments = ["Dock"]
                try? p.run()
            }
        case .menuBarAutoHide:
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("AppleInterfaceMenuBarHidingChangedNotification"), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }

    private typealias SetAutoHide = @convention(c) (Bool) -> Void
    private static let coreDockSetAutoHide: SetAutoHide? = {
        guard let h = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
            let sym = dlsym(h, "CoreDockSetAutoHideEnabled")
        else { return nil }
        return unsafeBitCast(sym, to: SetAutoHide.self)
    }()
}
