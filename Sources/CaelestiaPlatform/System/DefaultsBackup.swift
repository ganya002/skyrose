import CaelestiaCore
import CoreFoundation
import Foundation

/// Reads and writes preference keys. `nil` means "absent": writing it deletes the key.
public protocol PreferencesStore: AnyObject {
    func value(domain: String, key: String) -> Any?
    func set(_ value: Any?, domain: String, key: String)
}

/// The real store: `CFPreferences` for the current user, any host (what `defaults write` uses).
public final class CFPreferencesStore: PreferencesStore {
    public init() {}

    /// `NSGlobalDomain` / `-g` means every app (`kCFPreferencesAnyApplication`).
    static func cfDomain(_ domain: String) -> CFString {
        domain == "NSGlobalDomain" || domain == "-g" ? kCFPreferencesAnyApplication : domain as CFString
    }

    public func value(domain: String, key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, Self.cfDomain(domain))
    }

    public func set(_ value: Any?, domain: String, key: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList?, Self.cfDomain(domain))
        CFPreferencesAppSynchronize(Self.cfDomain(domain))
    }
}

/// Every `defaults` change goes through here (spec 10.4): the old value (or "absent") is recorded
/// in the backup journal BEFORE the write, and `restoreAll` puts every original back, deleting keys
/// that did not exist, then reads them back to verify. Never changes anything without a journal
/// entry; never deletes the journal.
public final class DefaultsBackup {
    public struct RestoreResult: Equatable, Sendable {
        public var domain: String
        public var key: String
        public var verified: Bool
    }

    public let journal: BackupJournal
    public let store: PreferencesStore

    public init(journal: BackupJournal = BackupJournal(), store: PreferencesStore = CFPreferencesStore()) {
        self.journal = journal
        self.store = store
    }

    /// Writes `value` (nil deletes) after journaling the current value. If the journal write
    /// fails, nothing is changed.
    public func write(_ value: Any?, domain: String, key: String, note: String? = nil) throws {
        try journal.append(BackupEntry(
            domain: domain, key: key, oldValue: BackupValue(plist: store.value(domain: domain, key: key)),
            newValue: BackupValue(plist: value), kind: .defaults, note: note
        ))
        store.set(value, domain: domain, key: key)
    }

    /// Restores the original value of every journaled `defaults` key, newest change first.
    @discardableResult
    public func restoreAll() throws -> [RestoreResult] {
        try journal.restorePlan().filter { $0.kind == .defaults }.map { entry in
            store.set(entry.oldValue.plistValue, domain: entry.domain, key: entry.key)
            let now = BackupValue(plist: store.value(domain: entry.domain, key: entry.key))
            return RestoreResult(domain: entry.domain, key: entry.key, verified: now == entry.oldValue)
        }
    }
}
