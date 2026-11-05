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

    /// Folder of the per-mode flag files (`<mode>-mode-used`). A second, tiny record next to the
    /// journal so a corrupt or deleted manifest still remembers that SIP-off mode was used.
    public let flagDirectory: URL

    public init(journal: BackupJournal = BackupJournal(url: Paths.restoreManifest), flagDirectory: URL = Paths.appSupport) {
        self.journal = journal
        self.flagDirectory = flagDirectory
    }

    public init(url: URL) {
        journal = BackupJournal(url: url)
        flagDirectory = url.deletingLastPathComponent()
    }

    /// Modes that change the system around SkyRose and need a manual step to undo.
    public enum Mode: String, Sendable, CaseIterable {
        /// System Integrity Protection partly off for the scripting addition ("SIP-off mode").
        case sipOff
    }

    static let modeDomain = "skyrose.mode"

    /// The flag file for `mode` (`sipOff-mode-used`): exists once the mode was used.
    public func flagURL(_ mode: Mode) -> URL { flagDirectory.appendingPathComponent("\(mode.rawValue)-mode-used") }

    /// Records that `mode` was used (once is enough; later calls add nothing). Writes the flag
    /// file first, then the journal entry.
    public func recordModeUsed(_ mode: Mode, note: String? = nil) throws {
        let flag = flagURL(mode)
        if !FileManager.default.fileExists(atPath: flag.path) {
            try FileManager.default.createDirectory(at: flagDirectory, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date())
            try Data("\(stamp)\n".utf8).write(to: flag, options: .atomic)
        }
        guard try !journal.contains(domain: Self.modeDomain, key: mode.rawValue) else { return }
        try journal.append(BackupEntry(domain: Self.modeDomain, key: mode.rawValue, oldValue: .bool(false), newValue: .bool(true),
                                       kind: .mode, note: note))
    }

    /// True when the flag file or the manifest records that `mode` was used. Nothing recorded
    /// (or an unreadable manifest without the flag) means it was not used.
    public func everUsed(_ mode: Mode) -> Bool {
        FileManager.default.fileExists(atPath: flagURL(mode).path)
            || ((try? journal.contains(domain: Self.modeDomain, key: mode.rawValue)) ?? false)
    }

    /// Whether the uninstaller shows the SIP reminder: only when SIP-off mode was actually used
    /// (``SIPReminderDecision``). `csrutilStatus` is the raw `csrutil status` output, nil when it
    /// could not be read.
    public func mustShowSIPReminder(csrutilStatus: String?) -> Bool {
        SIPReminderDecision.shouldShow(sipOffModeUsed: everUsed(.sipOff), status: SIPStatus.parse(csrutilStatus))
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
