import XCTest
import CaelestiaCore
@testable import CaelestiaPlatform

final class SystemTweaksTests: XCTestCase {
    final class MemoryStore: PreferencesStore {
        var values: [String: Any] = [:]
        var writes = 0
        func value(domain: String, key: String) -> Any? { values["\(domain)/\(key)"] }
        func set(_ value: Any?, domain: String, key: String) {
            writes += 1
            values["\(domain)/\(key)"] = value
        }
    }

    private var journalURL: URL!
    private var store: MemoryStore!
    private var tweaks: SystemTweaks!
    private var activations: [(SystemTweak.ID, Bool)] = []

    override func setUp() {
        journalURL = FileManager.default.temporaryDirectory.appendingPathComponent("tweaks-\(UUID().uuidString).json")
        store = MemoryStore()
        activations = []
        let backup = DefaultsBackup(journal: BackupJournal(url: journalURL), store: store)
        tweaks = SystemTweaks(backup: backup, activate: { [unowned self] id, on in self.activations.append((id, on)) })
    }

    override func tearDown() { try? FileManager.default.removeItem(at: journalURL) }

    func testApplyJournalsOldValueFirstAndWritesRecommended() throws {
        let t = SystemTweak.dockAutoHide
        store.values["com.apple.dock/autohide"] = false
        XCTAssertFalse(tweaks.isOn(t))
        XCTAssertFalse(tweaks.isChangedBySkyRose(t))
        try tweaks.apply(t)
        XCTAssertTrue(tweaks.isOn(t))
        XCTAssertTrue(tweaks.isChangedBySkyRose(t))
        let entries = try tweaks.backup.journal.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].oldValue, .bool(false))
        XCTAssertEqual(entries[0].newValue, .bool(true))
        XCTAssertEqual(activations.count, 1)
        XCTAssertEqual(activations[0].0, .dockAutoHide)
        XCTAssertTrue(activations[0].1)
    }

    func testApplyWhenAlreadyOnWritesNothing() throws {
        let t = SystemTweak.dockAutoHide
        store.values["com.apple.dock/autohide"] = true
        try tweaks.apply(t)
        XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(try tweaks.backup.journal.entries().isEmpty)
        XCTAssertTrue(activations.isEmpty)
        XCTAssertFalse(tweaks.isChangedBySkyRose(t))
    }

    func testUndoRestoresAbsentKey() throws {
        let t = SystemTweak.menuBarAutoHide
        XCTAssertNil(store.values["NSGlobalDomain/_HIHideMenuBar"])
        try tweaks.apply(t)
        XCTAssertTrue(tweaks.isOn(t))
        try tweaks.undo(t)
        XCTAssertFalse(tweaks.isOn(t))
        XCTAssertNil(store.values["NSGlobalDomain/_HIHideMenuBar"], "the key is absent again")
        XCTAssertFalse(tweaks.isChangedBySkyRose(t))
        XCTAssertEqual(activations.last?.1, false)
        XCTAssertEqual(try tweaks.backup.journal.entries().count, 2, "undo is journaled too")
    }

    func testUndoRestoresOriginalValue() throws {
        let t = SystemTweak.dockAutoHide
        store.values["com.apple.dock/autohide"] = false
        try tweaks.apply(t)
        try tweaks.undo(t)
        XCTAssertEqual((store.values["com.apple.dock/autohide"] as? NSNumber)?.boolValue, false)
    }

    func testUndoWithNothingRecordedDoesNothing() throws {
        try tweaks.undo(.dockAutoHide)
        XCTAssertEqual(store.writes, 0)
        XCTAssertTrue(activations.isEmpty)
    }

    func testCatalog() {
        XCTAssertEqual(SystemTweak.all.map(\.id), [.dockAutoHide, .menuBarAutoHide])
        XCTAssertTrue(SystemTweak.all.allSatisfy(\.recommended))
    }
}
