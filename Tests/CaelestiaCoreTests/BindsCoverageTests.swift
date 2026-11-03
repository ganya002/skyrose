import Foundation
import XCTest

@testable import CaelestiaCore

/// Every Hyprland bind in the live dump `Tests/fixtures/binds.json` must be mapped by a bind in
/// `keymap.default.toml` (spec 3.4 / 12.1).
final class BindsCoverageTests: XCTestCase {
    private struct FixtureBind: Decodable {
        var modmask: Int
        var key: String
        var locked: Bool
        var mouse: Bool
        var release: Bool
        var `repeat`: Bool
    }

    /// `SUPER+CTRL+ALT+SHIFT+key`: modifiers in a fixed order, key lower-cased.
    private static func normalized(modifiers: Set<LogicalModifier>, key: String) -> String {
        let mods = modifiers.sorted().map(\.rawValue)
        return (mods + [key.lowercased()]).joined(separator: "+")
    }

    private static func normalized(linuxChord text: String) -> String? {
        var modifiers = Set<LogicalModifier>()
        var key: String?
        for token in text.split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch token.uppercased() {
            case "SUPER": modifiers.insert(.superKey)
            case "ALT": modifiers.insert(.altKey)
            case "CTRL", "CONTROL": modifiers.insert(.ctrlKey)
            case "SHIFT": modifiers.insert(.shiftKey)
            default:
                guard key == nil else { return nil }
                key = token
            }
        }
        guard let key else { return nil }
        return normalized(modifiers: modifiers, key: key)
    }

    private static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fixtures", isDirectory: true)
    }

    private func loadFixture() throws -> [FixtureBind] {
        let data = try Data(contentsOf: Self.fixturesDirectory.appendingPathComponent("binds.json"))
        return try JSONDecoder().decode([FixtureBind].self, from: data)
    }

    private func linuxChords(of keymap: Keymap) throws -> [String: [Bind]] {
        var result: [String: [Bind]] = [:]
        for bind in keymap.binds {
            guard let linux = bind.linux else { continue }
            for part in linux.split(separator: "|").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                let key = try XCTUnwrap(Self.normalized(linuxChord: part), "unparseable linux chord \"\(part)\" in bind \(bind.id)")
                result[key, default: []].append(bind)
            }
        }
        return result
    }

    func testFixtureHasAllHyprlandBinds() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.count, 153, "binds.json is the live Hyprland dump with 153 entries")
    }

    func testEveryFixtureBindIsMapped() throws {
        let fixture = try loadFixture()
        let keymap = try KeymapLoader.loadDefaultOrThrow()
        let mapped = try linuxChords(of: keymap)

        var missing: [String] = []
        for entry in fixture {
            let wanted = Self.normalized(modifiers: LogicalModifier.fromHyprlandMask(entry.modmask), key: entry.key)
            if mapped[wanted] == nil { missing.append("modmask \(entry.modmask) key \(entry.key)  (\(wanted))") }
        }
        XCTAssertTrue(missing.isEmpty, "fixture binds without a `linux` mapping in keymap.default.toml:\n" + missing.joined(separator: "\n"))
    }

    func testMappedLinuxChordsAreExactlyTheFixture() throws {
        let fixture = try loadFixture()
        let keymap = try KeymapLoader.loadDefaultOrThrow()
        let mapped = try linuxChords(of: keymap)
        XCTAssertGreaterThanOrEqual(mapped.count, 153)

        let fixtureSet = Set(fixture.map { Self.normalized(modifiers: LogicalModifier.fromHyprlandMask($0.modmask), key: $0.key) })
        XCTAssertEqual(fixtureSet.count, 153, "every fixture entry is a distinct (modmask, key) pair")
        let extra = Set(mapped.keys).subtracting(fixtureSet)
        XCTAssertTrue(extra.isEmpty, "`linux` chords that are not in binds.json (the stock SUPER+SHIFT+ALT+S region bind must not ship): \(extra.sorted())")

        let duplicated = mapped.filter { $0.value.count > 1 }
        XCTAssertTrue(duplicated.isEmpty, "linux chords claimed by several binds: \(duplicated.map { "\($0.key): \($0.value.map(\.id))" })")
    }

    func testFlagsMatchHyprland() throws {
        let fixture = try loadFixture()
        let keymap = try KeymapLoader.loadDefaultOrThrow()
        let mapped = try linuxChords(of: keymap)
        var mismatches: [String] = []
        for entry in fixture {
            let wanted = Self.normalized(modifiers: LogicalModifier.fromHyprlandMask(entry.modmask), key: entry.key)
            guard let bind = mapped[wanted]?.first else { continue }
            var expected = Set<BindFlag>()
            if entry.locked { expected.insert(.locked) }
            if entry.mouse { expected.insert(.mouse) }
            if entry.release { expected.insert(.release) }
            if entry.repeat { expected.insert(.repeat) }
            if bind.flags != expected {
                mismatches.append("\(wanted): keymap \(bind.id) has \(bind.flags.map(\.rawValue).sorted()), Hyprland has \(expected.map(\.rawValue).sorted())")
            }
        }
        XCTAssertTrue(mismatches.isEmpty, mismatches.joined(separator: "\n"))
    }

    func testEveryBindHasValidActionAndArgs() throws {
        let keymap = try KeymapLoader.loadDefaultOrThrow()
        for bind in keymap.binds {
            let kind = bind.action.kind
            XCTAssertNotNil(ActionKind(rawValue: kind.rawValue), bind.id)
            for name in kind.requiredArgumentNames {
                XCTAssertNotNil(bind.action.args[name], "\(bind.id): \(kind.rawValue) needs \(name)")
            }
            for name in bind.action.args.keys {
                XCTAssertTrue(kind.argumentNames.contains(name), "\(bind.id): \(kind.rawValue) does not take \(name)")
            }
            XCTAssertFalse(bind.keys.isEmpty, bind.id)
            XCTAssertEqual(bind.keys.count, bind.chords.count, bind.id)
            XCTAssertFalse(bind.description.isEmpty, "\(bind.id) needs a description for the cheat sheet")
        }
    }

    func testWorkspaceDigitBinds() throws {
        let keymap = try KeymapLoader.loadDefaultOrThrow()
        let digitCodes: [Int: UInt16] = [1: 0x12, 2: 0x13, 3: 0x14, 4: 0x15, 5: 0x17, 6: 0x16, 7: 0x1A, 8: 0x1C, 9: 0x19, 10: 0x1D]
        for n in 1...10 {
            let code = digitCodes[n]!
            let focus = try XCTUnwrap(keymap.bind(id: "ws.focus.\(n)"))
            XCTAssertEqual(focus.action, Action(.workspaceFocus, index: n))
            XCTAssertEqual(focus.chords, [KeyChord(modifiers: [.superKey], key: .code(code))])
            XCTAssertEqual(try XCTUnwrap(keymap.bind(id: "ws.move.\(n)")).action, Action(.workspaceMove, index: n))
            XCTAssertEqual(try XCTUnwrap(keymap.bind(id: "ws.move.\(n)")).chords, [KeyChord(modifiers: [.superKey, .altKey], key: .code(code))])
            XCTAssertEqual(try XCTUnwrap(keymap.bind(id: "ws.moveSilent.\(n)")).action, Action(.workspaceMoveSilent, index: n))
            XCTAssertEqual(try XCTUnwrap(keymap.bind(id: "ws.moveSilent.\(n)")).chords, [KeyChord(modifiers: [.superKey, .shiftKey], key: .code(code))])
            XCTAssertEqual(try XCTUnwrap(keymap.bind(id: "ws.focusGroup.\(n)")).action, Action(.workspaceFocusGroup, group: n))
            XCTAssertEqual(try XCTUnwrap(keymap.bind(id: "ws.focusGroup.\(n)")).chords, [KeyChord(modifiers: [.superKey, .ctrlKey], key: .code(code))])
            XCTAssertEqual(try XCTUnwrap(keymap.bind(id: "ws.moveGroup.\(n)")).action, Action(.workspaceMoveGroup, group: n))
            XCTAssertEqual(try XCTUnwrap(keymap.bind(id: "ws.moveGroup.\(n)")).chords, [KeyChord(modifiers: [.superKey, .ctrlKey, .altKey], key: .code(code))])
        }
    }

    func testMacOnlyExtrasArePresent() throws {
        let keymap = try KeymapLoader.loadDefaultOrThrow()
        func chords(_ id: String) throws -> [KeyChord] { try XCTUnwrap(keymap.bind(id: id)).chords }
        XCTAssertTrue(try chords("capture.region").contains(try ChordParser.parse("SUPER + ALT + SHIFT + 4")))
        XCTAssertTrue(try chords("capture.region").contains(try ChordParser.parse("F13")))
        XCTAssertTrue(try chords("capture.full").contains(try ChordParser.parse("SUPER + ALT + SHIFT + 3")))
        XCTAssertTrue(try chords("capture.full").contains(try ChordParser.parse("SHIFT + F13")))
        XCTAssertTrue(try chords("session.menu").contains(try ChordParser.parse("CTRL + ALT + Backspace")))
        XCTAssertTrue(try chords("media.stop").contains(try ChordParser.parse("CTRL + SUPER + Backspace")))
        XCTAssertTrue(try chords("media.playPause").contains(try ChordParser.parse("Play")))
        XCTAssertTrue(try chords("media.playPause").contains(try ChordParser.parse("Pause")))
        XCTAssertTrue(try chords("audio.toggleMicMute").contains(try ChordParser.parse("SUPER + SHIFT + CTRL + M")))
        XCTAssertTrue(try chords("audio.volumeUp").contains(try ChordParser.parse("VolumeUp")))
        XCTAssertTrue(try chords("brightness.down").contains(try ChordParser.parse("BrightnessDown")))
        XCTAssertTrue(try chords("osd.numLock").contains(try ChordParser.parse("KeypadClear")))
        XCTAssertTrue(try chords("window.cycleNext").contains(try ChordParser.parse("SUPER + Tab")))
        XCTAssertTrue(try chords("group.prev").contains(try ChordParser.parse("CTRL + SUPER + SHIFT + Tab")))
        XCTAssertEqual(try chords("wm.panic"), [try ChordParser.parse("CTRL + ALT + SUPER + SHIFT + Escape")])
    }
}
