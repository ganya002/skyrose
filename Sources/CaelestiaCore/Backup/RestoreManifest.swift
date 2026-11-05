import Foundation

/// The restore manifest (`~/Library/Application Support/SkyRose/restore-manifest.json`): every
/// system change SkyRose makes — Dock and menu-bar auto-hide, keyboard shortcuts it turns off,
/// key remaps, login items, wallpapers, files — with the value from before the first change, so
/// the uninstaller (or the Undo button next to a tweak) puts the Mac back exactly as it was.
///
/// It is the ``BackupJournal`` file (same append-only JSON format, readable without Swift), plus
/// the questions an uninstaller asks: what is still changed, and was SIP-off mode ever used.
/// Writes for `defaults` keys go through `DefaultsBackup` (Platform), which records the entry
/// *before* changing anything.
public struct RestoreManifest: Sendable {
    public let journal: BackupJournal

    public init(journal: BackupJournal = BackupJournal(url: Paths.restoreManifest)) {
        self.journal = journal
    }

    public init(url: URL) {
        journal = BackupJournal(url: url)
    }

    /// Modes that change the system around SkyRose and need a manual step to undo.
    public enum Mode: String, Sendable, CaseIterable {
        /// System Integrity Protection partly off for the scripting addition ("SIP-off mode").
        case sipOff
    }

    static let modeDomain = "skyrose.mode"

    /// Records that `mode` was used (once is enough; later calls add nothing).
    public func recordModeUsed(_ mode: Mode, note: String? = nil) throws {
        guard try !journal.contains(domain: Self.modeDomain, key: mode.rawValue) else { return }
        try journal.append(BackupEntry(domain: Self.modeDomain, key: mode.rawValue, oldValue: .bool(false), newValue: .bool(true),
                                       kind: .mode, note: note))
    }

    /// True when the manifest records that `mode` was used. An unreadable manifest returns false
    /// here; ``mustShowSIPReminder`` treats that case as "maybe" and shows the reminder.
    public func everUsed(_ mode: Mode) -> Bool {
        ((try? journal.contains(domain: Self.modeDomain, key: mode.rawValue)) ?? false)
    }

    /// Whether the uninstaller must show the SIP reminder: SIP-off mode was recorded, or the
    /// manifest exists but cannot be read (then we cannot prove it was never used).
    public var mustShowSIPReminder: Bool {
        everUsed(.sipOff) || readError != nil
    }

    /// Why the manifest cannot be read, if it exists and is corrupt.
    public var readError: String? {
        do {
            _ = try journal.entries()
            return nil
        } catch {
            return String(describing: error)
        }
    }

    /// One line per setting still recorded, for the uninstaller and Settings › About.
    public struct Item: Equatable, Sendable, Identifiable {
        public var id: String
        public var kind: BackupEntry.Kind
        public var title: String
        public var original: BackupValue
        public var current: BackupValue
        public var changedAt: Date
    }

    /// The settings the uninstaller will restore, newest change first (modes excluded: they have
    /// nothing to write back).
    public func pendingRestores() throws -> [Item] {
        try journal.restorePlan().filter { $0.kind != .mode }.map { e in
            Item(id: e.id, kind: e.kind, title: Self.title(for: e), original: e.oldValue, current: e.newValue, changedAt: e.timestamp)
        }
    }

    /// Plain-English name of a recorded setting.
    public static func title(for e: BackupEntry) -> String {
        switch (e.kind, e.domain, e.key) {
        case (.defaults, "com.apple.dock", "autohide"): return "Dock: hide automatically"
        case (.defaults, "com.apple.dock", "autohide-delay"): return "Dock: show delay"
        case (.defaults, "NSGlobalDomain", "_HIHideMenuBar"): return "Menu bar: hide automatically"
        case (.defaults, "NSGlobalDomain", "AppleMenuBarVisibleInFullscreen"): return "Menu bar in full screen"
        case (.symbolichotkeys, _, let key): return "macOS keyboard shortcut #\(key)"
        case (.hidutil, _, let key): return "Key remap \(key)"
        case (.loginItem, _, let key): return "Open at login: \(key)"
        case (.wallpaper, let d, _): return "Wallpaper (\(d))"
        case (.mode, _, let key): return "Mode used: \(key)"
        default: return "\(e.domain) \(e.key)"
        }
    }
}
