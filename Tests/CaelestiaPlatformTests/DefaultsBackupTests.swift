import XCTest
import CaelestiaCore
@testable import CaelestiaPlatform

/// Backup/restore (spec 10.4, 12.1): write, restore, verify, "absent" keys deleted. Uses an
/// in-memory store; real preferences are never touched.
final class DefaultsBackupTests: XCTestCase {
    final class MemoryStore: PreferencesStore {
        var values: [String: Any] = [:]
        func value(domain: String, key: String) -> Any? { values["\(domain)/\(key)"] }
        func set(_ value: Any?, domain: String, key: String) { values["\(domain)/\(key)"] = value }
    }

    func makeJournal() -> BackupJournal {
        BackupJournal(url: FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString).json"))
    }

    func testWriteRestoreVerifyAndDeleteAbsentKeys() throws {
        let store = MemoryStore()
        store.values["com.apple.dock/autohide"] = false
        let journal = makeJournal()
        defer { try? FileManager.default.removeItem(at: journal.url) }
        let backup = DefaultsBackup(journal: journal, store: store)

        try backup.write(true, domain: "com.apple.dock", key: "autohide")
        try backup.write(1.0, domain: "NSGlobalDomain", key: "_HIHideMenuBar") // did not exist
        try backup.write(false, domain: "com.apple.dock", key: "autohide") // second change, same key
        XCTAssertEqual(store.values["NSGlobalDomain/_HIHideMenuBar"] as? Double, 1.0)

        let results = try backup.restoreAll()
        XCTAssertEqual(results.count, 2, "one restore per key")
        XCTAssertTrue(results.allSatisfy(\.verified))
        XCTAssertEqual(store.values["com.apple.dock/autohide"] as? Bool, false, "the ORIGINAL value comes back")
        XCTAssertNil(store.values["NSGlobalDomain/_HIHideMenuBar"], "absent keys are deleted")
        XCTAssertEqual(try journal.entries().count, 3, "the journal is append-only")
    }

    func testRestoreSkipsNonDefaultsEntries() throws {
        let journal = makeJournal()
        defer { try? FileManager.default.removeItem(at: journal.url) }
        try journal.append(BackupEntry(domain: "hidutil", key: "UserKeyMapping", oldValue: .string("{}"), newValue: .string("{}"), kind: .hidutil))
        XCTAssertEqual(try DefaultsBackup(journal: journal, store: MemoryStore()).restoreAll(), [])
    }
}
