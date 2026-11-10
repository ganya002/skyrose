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

    func testDockRemovalJournalsEveryOriginalIncludingAbsentKeys() throws {
        store.values["com.apple.dock/autohide"] = false
        store.values["com.apple.dock/autohide-delay"] = 0.5
        store.values["com.apple.dock/tilesize"] = 48
        var restarts = 0
        let removal = DockRemoval(backup: tweaks.backup, restart: { restarts += 1 })
        XCTAssertFalse(removal.isHidden())
        try removal.hide()
        XCTAssertEqual(restarts, 1)
        XCTAssertTrue(removal.isHidden())
        let entries = try tweaks.backup.journal.entries()
        XCTAssertEqual(entries.map(\.key), ["autohide", "autohide-delay", "autohide-time-modifier", "tilesize"])
        XCTAssertEqual(entries[0].oldValue, .bool(false))
        XCTAssertEqual(entries[1].oldValue, .double(0.5))
        XCTAssertEqual(entries[2].oldValue, .absent)
        XCTAssertEqual(entries[3].oldValue, .int(48))
        try removal.hide()
        XCTAssertEqual(restarts, 1, "already hidden: nothing is written again")
        try removal.show()
        XCTAssertEqual(restarts, 2)
        XCTAssertEqual((store.values["com.apple.dock/autohide"] as? NSNumber)?.boolValue, false)
        XCTAssertEqual((store.values["com.apple.dock/autohide-delay"] as? NSNumber)?.doubleValue ?? -1, 0.5, accuracy: 0.001)
        XCTAssertNil(store.values["com.apple.dock/autohide-time-modifier"])
        XCTAssertEqual((store.values["com.apple.dock/tilesize"] as? NSNumber)?.intValue, 48)
        XCTAssertFalse(removal.isHidden())
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
    // MARK: Apple menu bar choice

    private var menuDirectory: URL { journalURL.deletingPathExtension() }
    private var hideFlag: Any? { store.values["NSGlobalDomain/_HIHideMenuBar"] }

    @MainActor func testMenuBarWithNoSavedChoiceReportsWhatMacOSIsDoing() {
        XCTAssertEqual(SystemMenuBar.current(tweaks: tweaks, directory: menuDirectory), .shown)
        store.values["NSGlobalDomain/_HIHideMenuBar"] = true
        XCTAssertEqual(SystemMenuBar.current(tweaks: tweaks, directory: menuDirectory), .auto)
    }

    @MainActor func testMenuBarChoiceSurvivesARestartAndYieldsToSystemSettings() throws {
        try SystemMenuBar.apply(.off, tweaks: tweaks, directory: menuDirectory)
        XCTAssertEqual(hideFlag as? Bool, true)
        XCTAssertEqual(SystemMenuBar.current(tweaks: tweaks, directory: menuDirectory), .off, "read back from disk")
        store.values["NSGlobalDomain/_HIHideMenuBar"] = false
        XCTAssertEqual(SystemMenuBar.current(tweaks: tweaks, directory: menuDirectory), .shown)
    }

    @MainActor func testAutoHideToOffStillTellsTheWindowManager() throws {
        try SystemMenuBar.apply(.auto, tweaks: tweaks, directory: menuDirectory)
        activations = []
        let writes = store.writes
        try SystemMenuBar.apply(.off, tweaks: tweaks, directory: menuDirectory)
        XCTAssertEqual(store.writes, writes, "the flag is already right")
        XCTAssertEqual(activations.count, 1, "the layout inset changed even though the flag did not")
        XCTAssertEqual(MenuBarChoiceStore.read(MenuBarChoiceStore.file(in: menuDirectory)), .off)
    }

    @MainActor func testPeekPutsAutoHideBackEvenWithNoSavedChoice() {
        store.values["NSGlobalDomain/_HIHideMenuBar"] = true
        SystemMenuBar.peek(tweaks: tweaks, seconds: 0.05)
        XCTAssertEqual(hideFlag as? Bool, false, "shown during the peek")
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertEqual(hideFlag as? Bool, true, "hidden again")
    }

    @MainActor func testPeekLeavesAShownBarAlone() {
        SystemMenuBar.peek(tweaks: tweaks, seconds: 0.05)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertEqual(store.writes, 0)
    }

    @MainActor func testAChoiceMadeDuringAPeekIsNotUndoneByIt() throws {
        store.values["NSGlobalDomain/_HIHideMenuBar"] = true
        SystemMenuBar.peek(tweaks: tweaks, seconds: 0.05)
        try SystemMenuBar.apply(.shown, tweaks: tweaks, directory: menuDirectory)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(hideFlag as? Bool, false)
    }
}
