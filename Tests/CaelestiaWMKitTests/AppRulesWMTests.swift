import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CoreGraphics
import XCTest

@testable import CaelestiaWMKit

/// `WindowManager+AppRules`: the per-app rules API (entries, set, persist, live re-tiling) and its
/// IPC commands.
@MainActor
final class AppRulesWMTests: XCTestCase {
    private struct Failure: Error {}

    private func rpc(_ h: Harness, _ command: IPCCommand, _ args: [String: JSONValue] = [:]) -> IPCResponse {
        h.wm.respond(to: IPCRequest(command, args: args)).response
    }

    // MARK: window placement by rule

    func testCalculatorFloatsByDefaultAndFinderTiles() {
        let h = Harness()
        let calc = h.system.existing("calc", bundle: "com.apple.calculator")
        let finder = h.system.existing("finder", bundle: "com.apple.finder")
        h.start()
        XCTAssertTrue(h.wm.isFloating(calc.windowID))
        XCTAssertFalse(h.wm.isFloating(finder.windowID))
    }

    func testFloatRuleFloatsAnAppsNewWindowsAndTileRuleTilesBuiltIns() {
        var config = Config()
        config.appRules = ["com.example.app": "float", "com.apple.calculator": "tile"]
        let h = Harness(config: config)
        let calc = h.system.existing("calc", bundle: "com.apple.calculator")
        let app = h.system.existing("app", bundle: "com.example.app")
        h.start()
        XCTAssertFalse(h.wm.isFloating(calc.windowID), "user tile overrides the built-in float")
        XCTAssertTrue(h.wm.isFloating(app.windowID))
    }

    func testTileRuleStillFloatsDialogs() {
        var config = Config()
        config.appRules = ["com.example.app": "tile"]
        let h = Harness(config: config)
        let dialog = h.system.existing("dlg", bundle: "com.example.app")
        dialog.subrole = "AXDialog"
        h.start()
        XCTAssertTrue(h.wm.isFloating(dialog.windowID))
    }

    // MARK: entries

    func testEntriesListRunningAppsRuledAppsAndBuiltIns() {
        var config = Config()
        config.appRules = ["com.example.ruled": "float"]
        let h = Harness(config: config)
        h.wm.runningApps = { [("com.apple.finder", "Finder"), ("com.example.idle", "Idle")] }
        h.system.existing("one", bundle: "com.apple.finder")
        h.system.existing("two", bundle: "com.apple.finder")
        h.start()

        let entries = h.wm.appRuleEntries()
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.bundleID, $0) })
        XCTAssertEqual(byID["com.apple.finder"]?.name, "Finder")
        XCTAssertEqual(byID["com.apple.finder"]?.windows, 2)
        XCTAssertEqual(byID["com.apple.finder"]?.floatingWindows, 0)
        XCTAssertEqual(byID["com.apple.finder"]?.running, true)
        XCTAssertEqual(byID["com.apple.finder"]?.mode, "auto")
        XCTAssertEqual(byID["com.apple.finder"]?.rule, "auto")
        XCTAssertEqual(byID["com.apple.finder"]?.source, "none")
        XCTAssertEqual(byID["com.example.idle"]?.running, true)
        XCTAssertEqual(byID["com.example.idle"]?.windows, 0)
        XCTAssertEqual(byID["com.example.ruled"]?.rule, "float")
        XCTAssertEqual(byID["com.example.ruled"]?.source, "user")
        XCTAssertEqual(byID["com.example.ruled"]?.running, false)
        XCTAssertEqual(byID["com.apple.calculator"]?.name, "Calculator")
        XCTAssertEqual(byID["com.apple.calculator"]?.mode, "float")
        XCTAssertEqual(byID["com.apple.calculator"]?.source, "builtIn")
        XCTAssertEqual(byID["com.apple.calculator"]?.rule, "auto")
        XCTAssertEqual(entries.count, Set(entries.map(\.bundleID)).count, "no duplicates")
        // Running apps come first.
        let firstIdle = entries.firstIndex { !$0.running }!
        XCTAssertTrue(entries[..<firstIdle].allSatisfy(\.running))
        XCTAssertTrue(entries[firstIdle...].allSatisfy { !$0.running })
    }

    func testEntryForABundleCountsFloatingWindows() {
        let h = Harness()
        h.system.existing("a", bundle: "com.example.app")
        let dialog = h.system.existing("d", bundle: "com.example.app")
        dialog.subrole = "AXDialog"
        h.start()
        let e = h.wm.appRuleEntry(for: "COM.example.APP")
        XCTAssertEqual(e.windows, 2)
        XCTAssertEqual(e.floatingWindows, 1)
        XCTAssertTrue(e.running)
        XCTAssertEqual(h.wm.appRuleEntry(for: "com.nobody").windows, 0)
        XCTAssertFalse(h.wm.appRuleEntry(for: "com.nobody").running)
    }

    func testFocusedAppRule() {
        let h = Harness()
        XCTAssertNil(h.wm.focusedAppRule())
        let w = h.system.existing("w", bundle: "com.example.app")
        h.start()
        h.wm.state.recordFocus(w.windowID)
        XCTAssertEqual(h.wm.focusedAppRule()?.bundleID, "com.example.app")
    }

    // MARK: set

    func testSetAppRulePersistsAndFloatsOpenWindowsImmediately() throws {
        let h = Harness()
        var saved: [(String, AppLayoutMode)] = []
        h.wm.appRulePersister = { saved.append(($0, $1)) }
        let a = h.system.existing("a", bundle: "com.example.app")
        let b = h.system.existing("b", bundle: "com.example.app")
        let other = h.system.existing("o", bundle: "com.example.other")
        h.start()
        XCTAssertFalse(h.wm.isFloating(a.windowID))

        let entry = try h.wm.setAppRule(.float, for: "com.example.app")
        h.settle()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.0, "com.example.app")
        XCTAssertEqual(saved.first?.1, .float)
        XCTAssertEqual(entry.rule, "float")
        XCTAssertEqual(entry.source, "user")
        XCTAssertEqual(entry.floatingWindows, 2)
        XCTAssertTrue(h.wm.isFloating(a.windowID))
        XCTAssertTrue(h.wm.isFloating(b.windowID))
        XCTAssertFalse(h.wm.isFloating(other.windowID), "other apps are untouched")
        let area = h.wm.usableArea(of: TestDisplays.air)
        XCTAssertTrue(area.contains(a.frame))
        XCTAssertEqual(h.wm.config.appRules["com.example.app"], "float")
    }

    func testSetTileTilesAFloatingBuiltInAndAutoRestoresIt() throws {
        let h = Harness()
        let calc = h.system.existing("calc", bundle: "com.apple.calculator")
        h.system.existing("x", bundle: "com.example.app")
        h.start()
        XCTAssertTrue(h.wm.isFloating(calc.windowID))
        try h.wm.setAppRule(.tile, for: "com.apple.calculator")
        h.settle()
        XCTAssertFalse(h.wm.isFloating(calc.windowID))
        XCTAssertNotNil(h.wm.visiblePlacements[calc.windowID])
        try h.wm.setAppRule(.auto, for: "com.apple.calculator")
        h.settle()
        XCTAssertTrue(h.wm.isFloating(calc.windowID), "auto falls back to the built-in float")
        XCTAssertNil(h.wm.config.appRules["com.apple.calculator"])
    }

    func testSettingTheSameModeLeavesHandMovedWindowsAlone() throws {
        let h = Harness()
        let a = h.system.existing("a", bundle: "com.example.app")
        h.system.existing("b")
        h.start()
        try h.wm.setAppRule(.tile, for: "com.example.app")  // effective mode stays auto -> tile: floats() unchanged
        h.settle()
        XCTAssertFalse(h.wm.isFloating(a.windowID))
    }

    func testEmptyBundleIDThrowsAndPersistFailureSurfaces() {
        let h = Harness()
        XCTAssertThrowsError(try h.wm.setAppRule(.float, for: "")) { XCTAssertEqual($0 as? AppRuleError, .emptyBundleID) }
        XCTAssertThrowsError(try h.wm.setAppRule(.float, for: "   ")) { XCTAssertEqual($0 as? AppRuleError, .emptyBundleID) }
        h.wm.appRulePersister = { _, _ in throw Failure() }
        XCTAssertThrowsError(try h.wm.setAppRule(.float, for: "com.x")) {
            guard case .persistFailed = $0 as? AppRuleError else { return XCTFail("\($0)") }
        }
        XCTAssertNil(h.wm.config.appRules["com.x"], "a rule that could not be saved is not applied")
    }

    func testBundleIDIsTrimmed() throws {
        let h = Harness()
        var saved: [String] = []
        h.wm.appRulePersister = { id, _ in saved.append(id) }
        try h.wm.setAppRule(.float, for: "  com.x  ")
        XCTAssertEqual(saved, ["com.x"])
    }

    // MARK: IPC

    func testIPCRulesAppsSetAndFocused() throws {
        let h = Harness()
        var saved: [(String, AppLayoutMode)] = []
        h.wm.appRulePersister = { saved.append(($0, $1)) }
        let w = h.system.existing("w", bundle: "com.example.app")
        h.start()
        h.wm.state.recordFocus(w.windowID)

        let set = rpc(h, .rulesSet, ["bundleID": .string("com.example.app"), "mode": .string("FLOAT")])
        XCTAssertTrue(set.ok, set.error ?? "")
        let entry = try XCTUnwrap(set.result).decode(AppRuleEntry.self)
        XCTAssertEqual(entry.bundleID, "com.example.app")
        XCTAssertEqual(entry.rule, "float")
        XCTAssertEqual(saved.map(\.0), ["com.example.app"])
        h.settle()
        XCTAssertTrue(h.wm.isFloating(w.windowID))

        let apps = rpc(h, .rulesApps)
        XCTAssertTrue(apps.ok)
        let list = try XCTUnwrap(apps.result).decode([AppRuleEntry].self)
        XCTAssertEqual(list.first { $0.bundleID == "com.example.app" }?.rule, "float")
        XCTAssertNotNil(list.first { $0.bundleID == "com.apple.systempreferences" })

        let focused = rpc(h, .rulesFocused)
        XCTAssertTrue(focused.ok)
        XCTAssertEqual(try XCTUnwrap(focused.result).decode(AppRuleEntry.self).bundleID, "com.example.app")
    }

    func testIPCRulesFocusedWithNoWindowIsNull() {
        let h = Harness()
        h.start()
        let r = rpc(h, .rulesFocused)
        XCTAssertTrue(r.ok)
        XCTAssertTrue(r.result == nil || r.result == .null)
    }

    func testIPCRulesSetRefusesBadArguments() {
        let h = Harness()
        XCTAssertFalse(rpc(h, .rulesSet, ["mode": .string("float")]).ok)
        XCTAssertFalse(rpc(h, .rulesSet, ["bundleID": .string(""), "mode": .string("float")]).ok)
        XCTAssertFalse(rpc(h, .rulesSet, ["bundleID": .string("com.x")]).ok)
        let bad = rpc(h, .rulesSet, ["bundleID": .string("com.x"), "mode": .string("sideways")])
        XCTAssertFalse(bad.ok)
        XCTAssertTrue(bad.error?.contains("tile") == true)
        XCTAssertNil(h.wm.config.appRules["com.x"])
    }
}
