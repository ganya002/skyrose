import Foundation
import XCTest

@testable import CaelestiaCore

final class ConflictCheckerTests: XCTestCase {
    private static var plistURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/symbolichotkeys.plist")
    }

    /// A keymap with just the panic bind plus `binds`, under `modifiers`.
    private func makeKeymap(modifiers: ModifierMap = .optionIsSuper, binds: [Bind]) throws -> Keymap {
        var all = binds
        all.append(KeymapParser.panicBind)
        let toml = KeymapParser.serialize(Keymap(modifiers: modifiers, binds: all))
        var warnings: [String] = []
        let parsed = try KeymapParser.parse(toml: toml, warnings: &warnings)
        XCTAssertEqual(warnings, [])
        return parsed
    }

    private func bind(_ id: String, _ keys: [String], _ action: Action, enabled: Bool = true) -> Bind {
        Bind(id: id, keys: keys, action: action, enabled: enabled)
    }

    private func check(_ keymap: Keymap, layout: any KeyboardLayoutCharacters = USQwertyCharacters(), isLaptop: Bool = true) -> ConflictReport {
        ConflictChecker(keymap: keymap, layout: layout, systemHotkeysPlist: Self.plistURL, isLaptop: isLaptop).check()
    }

    // MARK: 1. Duplicates

    func testSeededDuplicateIsAnError() throws {
        var keymap = try KeymapLoader.loadDefaultOrThrow()
        keymap.binds.append(Bind(id: "dup", keys: ["SUPER + 1"], action: Action(.lock), chords: [try ChordParser.parse("SUPER + 1")]))
        let report = check(keymap)
        let duplicates = report.items.filter { $0.category == ConflictItem.duplicateCategory }
        XCTAssertEqual(duplicates.count, 1)
        let item = try XCTUnwrap(duplicates.first)
        XCTAssertEqual(item.severity, .error)
        XCTAssertEqual(item.bindID, "dup")
        XCTAssertEqual(item.chord, "SUPER + 1")
        XCTAssertTrue(item.message.contains("ws.focus.1"), item.message)
        XCTAssertTrue(item.message.contains("dup"), item.message)
        XCTAssertNotNil(item.fix)
        XCTAssertGreaterThanOrEqual(report.errorCount, 1)
    }

    func testDisabledBindsDoNotCountAsDuplicates() throws {
        let keymap = try makeKeymap(binds: [
            bind("a", ["SUPER + 1"], Action(.lock)),
            bind("b", ["SUPER + 1"], Action(.sidebarToggle), enabled: false),
        ])
        XCTAssertTrue(check(keymap).items.filter { $0.category == ConflictItem.duplicateCategory }.isEmpty)
    }

    func testSameActionTwiceIsOnlyAWarning() throws {
        let keymap = try makeKeymap(binds: [
            bind("a", ["SUPER + 1"], Action(.lock)),
            bind("b", ["SUPER + 1"], Action(.lock)),
        ])
        let items = check(keymap).items.filter { $0.category == ConflictItem.duplicateCategory }
        XCTAssertEqual(items.map(\.severity), [.warn])
    }

    func testDefaultKeymapErrorsUnderPresetAAreOnlyKnownSystemClashes() throws {
        let report = check(try KeymapLoader.loadDefaultOrThrow())
        let errors = report.items.filter { $0.severity == .error }
        XCTAssertTrue(errors.filter { $0.category == ConflictItem.duplicateCategory }.isEmpty, "\(errors)")
        // CTRL + SUPER + Space = ⌃⌥Space is "Select next source in Input menu" and SUPER + ALT + Space =
        // ⌥⌘Space is "Show Finder search window"; both are enabled in the fixture plist.
        XCTAssertEqual(errors.map(\.bindID), ["media.playPause", "window.toggleFloat"], "\(errors)")
        XCTAssertTrue(errors.allSatisfy { $0.category == ConflictItem.systemCategory })
    }

    // MARK: 2. macOS system shortcuts

    func testControlDigitClashesWithSwitchToDesktop() throws {
        let keymap = try makeKeymap(binds: [
            bind("ctrl1", ["CTRL + 1"], Action(.lock)),
            bind("ctrl5", ["CTRL + 5"], Action(.sidebarToggle)),
        ])
        let system = check(keymap).items.filter { $0.category == ConflictItem.systemCategory }
        XCTAssertEqual(system.map(\.bindID), ["ctrl1"], "⌃1 is enabled in the fixture, ⌃5 is disabled")
        let item = try XCTUnwrap(system.first)
        XCTAssertEqual(item.severity, .error)
        XCTAssertEqual(item.chord, "CTRL + 1")
        XCTAssertTrue(item.message.contains("Switch to Desktop 1"), item.message)
        XCTAssertTrue(item.message.contains("⌃1"), item.message)
        XCTAssertTrue(item.fix?.contains("symbolichotkeys id 118") == true, item.fix ?? "nil")
        XCTAssertTrue(item.fix?.contains("backing up") == true, item.fix ?? "nil")
    }

    func testOptionDigitDoesNotClashUnderPresetA() throws {
        let keymap = try KeymapLoader.loadDefaultOrThrow()
        let system = check(keymap).items.filter { $0.category == ConflictItem.systemCategory }
        XCTAssertFalse(system.contains { $0.bindID == "ws.focus.1" }, "SUPER + 1 is ⌥1, not ⌃1")
        XCTAssertFalse(system.contains { $0.bindID == "ws.focusGroup.1" }, "SUPER + CTRL + 1 is ⌃⌥1, not ⌃1")
        XCTAssertFalse(system.contains { $0.bindID == "ws.prev" }, "SUPER + CTRL + Left is ⌃⌥←, not ⌃←")
    }

    func testSpotlightClashUnderPresetC() throws {
        let keymap = try makeKeymap(modifiers: .commandIsSuper, binds: [bind("launcher", ["SUPER + Space"], Action(.launcherToggle))])
        let system = check(keymap).items.filter { $0.category == ConflictItem.systemCategory }
        XCTAssertEqual(system.count, 1)
        let item = try XCTUnwrap(system.first)
        XCTAssertEqual(item.severity, .error)
        XCTAssertEqual(item.bindID, "launcher")
        XCTAssertTrue(item.message.contains("Spotlight"), item.message)
        XCTAssertTrue(item.message.contains("⌘Space"), item.message)
        XCTAssertTrue(item.fix?.contains("symbolichotkeys id 64") == true, item.fix ?? "nil")
    }

    func testFixedShortcutsCannotBeOverridden() throws {
        let keymap = try makeKeymap(modifiers: .commandIsSuper, binds: [
            bind("cycle", ["SUPER + Tab"], Action(.windowCycleNext)),
            bind("quit", ["SUPER + SHIFT + Q"], Action(.windowClose)),
            bind("force", ["ALT + SUPER + Escape"], Action(.wmPanic)),
        ])
        let system = check(keymap).items.filter { $0.category == ConflictItem.systemCategory }
        XCTAssertEqual(Set(system.map(\.bindID)), ["cycle", "quit", "force"])
        for item in system {
            XCTAssertEqual(item.severity, .error)
            XCTAssertTrue(item.message.contains("fixed"), item.message)
            XCTAssertTrue(item.fix?.contains("cannot be turned off") == true, item.fix ?? "nil")
        }
    }

    func testMissionControlAndSpacesFromFixture() throws {
        let keymap = try makeKeymap(modifiers: ModifierMap(superKey: .ctrl, altKey: .lcmd, ctrlKey: .lopt, shiftKey: .shift), binds: [
            bind("up", ["SUPER + Up"], Action(.windowFocus, direction: .up)),
            bind("left", ["SUPER + Left"], Action(.windowFocus, direction: .left)),
            bind("shot", ["ALT + SHIFT + 4"], Action(.captureRegion)),
            bind("input", ["SUPER + Space"], Action(.launcherToggle)),
        ])
        let names = check(keymap).items.filter { $0.category == ConflictItem.systemCategory }.map(\.message)
        XCTAssertTrue(names.contains { $0.contains("Mission Control") }, "\(names)")
        XCTAssertTrue(names.contains { $0.contains("Move left a space") }, "\(names)")
        XCTAssertTrue(names.contains { $0.contains("selected area") }, "\(names)")
        XCTAssertTrue(names.contains { $0.contains("previous input source") }, "\(names)")
    }

    func testMissingPlistFallsBackToMacOSDefaults() throws {
        let keymap = try makeKeymap(modifiers: .commandIsSuper, binds: [bind("launcher", ["SUPER + Space"], Action(.launcherToggle))])
        let missing = URL(fileURLWithPath: "/nonexistent/com.apple.symbolichotkeys.plist")
        let report = ConflictChecker(keymap: keymap, systemHotkeysPlist: missing).check()
        XCTAssertTrue(report.items.contains { $0.category == ConflictItem.systemCategory && $0.message.contains("Spotlight") })
        let hotkeys = SystemHotkey.effective(plist: missing)
        XCTAssertFalse(hotkeys.first { $0.id == 118 }!.enabled, "Switch to Desktop is off by default")
    }

    // MARK: 3. App shortcuts

    func testCommandAppShortcutsWarnUnderPresetC() throws {
        let keymap = try makeKeymap(modifiers: .commandIsSuper, binds: [
            bind("close", ["SUPER + Q"], Action(.windowClose)),
            bind("browser", ["SUPER + W"], Action(.appBrowser)),
            bind("ok", ["SUPER + SHIFT + Q"], Action(.lock)),
            bind("ctrl", ["CTRL + SUPER + C"], Action(.lock)),
        ])
        let app = check(keymap).items.filter { $0.category == ConflictItem.appCategory }
        XCTAssertEqual(Set(app.map(\.bindID)), ["close", "browser"])
        let close = try XCTUnwrap(app.first { $0.bindID == "close" })
        XCTAssertEqual(close.severity, .warn)
        XCTAssertTrue(close.message.contains("Quit"), close.message)
        XCTAssertTrue(close.message.contains("swallows"), close.message)
    }

    func testNoAppShortcutWarningsWithoutACommandModifier() throws {
        let keymap = try makeKeymap(modifiers: .capsLockIsHyper, binds: [bind("close", ["SUPER + Q"], Action(.windowClose))])
        XCTAssertTrue(check(keymap).items.filter { $0.category == ConflictItem.appCategory }.isEmpty)
        let presetA = try KeymapLoader.loadDefaultOrThrow()
        XCTAssertTrue(check(presetA).items.filter { $0.category == ConflictItem.appCategory }.isEmpty, "no ALT-only binds ship under preset A")
    }

    // MARK: 4. Option characters

    func testOptionCharacterInfoRowsUnderPresetA() throws {
        let report = check(try KeymapLoader.loadDefaultOrThrow())
        let option = report.items.filter { $0.category == ConflictItem.optionCharCategory }
        XCTAssertFalse(option.isEmpty)
        for item in option { XCTAssertEqual(item.severity, .info) }
        let q = try XCTUnwrap(option.first { $0.bindID == "window.close" })
        XCTAssertEqual(q.chord, "SUPER + Q")
        XCTAssertTrue(q.message.contains("\"œ\""), q.message)
        XCTAssertTrue(q.message.contains("U.S."), q.message)
        XCTAssertTrue(q.message.contains("RIGHT Option"), q.message)
        XCTAssertTrue(q.fix?.contains("Right Option") == true, q.fix ?? "nil")
        let shifted = try XCTUnwrap(option.first { $0.bindID == "capture.freeze" })
        XCTAssertTrue(shifted.message.contains("\"Í\""), "⌥⇧S is Í on the U.S. layout: \(shifted.message)")
        XCTAssertFalse(option.contains { $0.bindID == "window.focus.left" }, "arrows produce no character")
        XCTAssertFalse(option.contains { $0.bindID == "ws.focusGroup.1" }, "⌃⌥1 is not an Option character")
    }

    func testOptionCharactersAreWarningsWhenBothOptionKeysAreSuper() throws {
        let keymap = try makeKeymap(modifiers: ModifierMap(superKey: .opt, altKey: .lcmd, ctrlKey: .ctrl, shiftKey: .shift), binds: [
            bind("q", ["SUPER + Q"], Action(.windowClose)),
        ])
        let item = try XCTUnwrap(check(keymap).items.first { $0.category == ConflictItem.optionCharCategory })
        XCTAssertEqual(item.severity, .warn)
        XCTAssertTrue(item.message.contains("cannot be typed"), item.message)
    }

    func testOptionCharactersUseTheGivenLayout() throws {
        struct Norwegian: KeyboardLayoutCharacters {
            var layoutName: String { "Norwegian" }
            func character(forKeyCode code: UInt16, shift: Bool) -> String? { nil }
            func optionCharacter(forKeyCode code: UInt16, shift: Bool) -> String? { code == 0x0C ? "•" : nil }
        }
        let keymap = try makeKeymap(binds: [bind("q", ["SUPER + Q"], Action(.windowClose)), bind("w", ["SUPER + W"], Action(.appBrowser))])
        let option = check(keymap, layout: Norwegian()).items.filter { $0.category == ConflictItem.optionCharCategory }
        XCTAssertEqual(option.map(\.bindID), ["q"])
        XCTAssertTrue(option[0].message.contains("\"•\" on the Norwegian layout"), option[0].message)
    }

    // MARK: 5. Keys a MacBook lacks

    func testMissingKeyInfoRows() throws {
        let report = check(try KeymapLoader.loadDefaultOrThrow())
        let missing = report.items.filter { $0.category == ConflictItem.missingKeyCategory }
        let byBind = Dictionary(grouping: missing, by: { $0.bindID ?? "" })
        XCTAssertNotNil(byBind["ws.next"])
        XCTAssertNotNil(byBind["ws.prev"])
        XCTAssertNotNil(byBind["session.menu"])
        XCTAssertNotNil(byBind["capture.region"])
        XCTAssertNotNil(byBind["capture.full"])
        XCTAssertNotNil(byBind["osd.numLock"])
        for item in missing { XCTAssertEqual(item.severity, .info, "\(item)") }

        let pageDown = try XCTUnwrap(byBind["ws.next"]?.first)
        XCTAssertEqual(pageDown.chord, "SUPER + PageDown")
        XCTAssertTrue(pageDown.message.contains("⌥L fn ↓"), pageDown.message)
        let delete = try XCTUnwrap(byBind["session.menu"]?.first)
        XCTAssertTrue(delete.message.contains("fn ⌫"), delete.message)
        let f13 = try XCTUnwrap(byBind["capture.region"]?.first)
        XCTAssertEqual(f13.chord, "F13")
        XCTAssertTrue(f13.message.contains("SUPER + ALT + SHIFT + 4"), f13.message)
        let numLock = try XCTUnwrap(byBind["osd.numLock"]?.first)
        XCTAssertEqual(numLock.severity, .info)
        XCTAssertNil(numLock.fix)
        XCTAssertFalse(missing.contains { $0.bindID == "ws.focus.1" })
    }

    func testMissingKeyWithoutAlternativeIsAWarning() throws {
        let keymap = try makeKeymap(binds: [bind("help", ["SUPER + Help"], Action(.lock))])
        let item = try XCTUnwrap(check(keymap).items.first { $0.category == ConflictItem.missingKeyCategory })
        XCTAssertEqual(item.severity, .warn)
        XCTAssertTrue(item.fix?.contains("Add a chord") == true, item.fix ?? "nil")
    }

    func testNoMissingKeyRowsOnDesktops() throws {
        let report = check(try KeymapLoader.loadDefaultOrThrow(), isLaptop: false)
        XCTAssertTrue(report.items.filter { $0.category == ConflictItem.missingKeyCategory }.isEmpty)
    }

    // MARK: Report

    func testReportCountsAndTable() throws {
        var keymap = try KeymapLoader.loadDefaultOrThrow()
        keymap.binds.append(Bind(id: "dup", keys: ["SUPER + 1"], action: Action(.lock), chords: [try ChordParser.parse("SUPER + 1")]))
        let report = check(keymap)
        XCTAssertEqual(report.errorCount, report.items.filter { $0.severity == .error }.count)
        XCTAssertEqual(report.warnCount, report.items.filter { $0.severity == .warn }.count)
        XCTAssertEqual(report.infoCount, report.items.filter { $0.severity == .info }.count)
        XCTAssertEqual(report.errorCount + report.warnCount + report.infoCount, report.items.count)
        XCTAssertFalse(report.isClean)
        XCTAssertEqual(report.items.first?.severity, .error, "errors sort first")

        let table = report.formattedTable()
        XCTAssertTrue(table.hasPrefix("SEVERITY"), table)
        XCTAssertTrue(table.contains("ERROR"))
        XCTAssertTrue(table.contains("dup"))
        XCTAssertTrue(table.hasSuffix("info"), table.suffix(60).description)
        XCTAssertEqual(table.components(separatedBy: "\n").count, report.items.count + 4)

        XCTAssertEqual(ConflictReport(items: []).formattedTable(), "No conflicts found.")
        let json = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(ConflictReport.self, from: json).items, report.items)
    }
}
