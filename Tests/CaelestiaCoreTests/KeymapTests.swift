import Foundation
import XCTest

@testable import CaelestiaCore

final class KeymapTests: XCTestCase {
    // MARK: - Chord parsing

    func testParsesModifierAndKeyChords() throws {
        XCTAssertEqual(try ChordParser.parse("SUPER + SHIFT + Left"), KeyChord(modifiers: [.superKey, .shiftKey], key: .code(0x7B)))
        XCTAssertEqual(try ChordParser.parse("CTRL + ALT + Delete"), KeyChord(modifiers: [.ctrlKey, .altKey], key: .code(0x75)))
        XCTAssertEqual(try ChordParser.parse("super + shift + left"), KeyChord(modifiers: [.superKey, .shiftKey], key: .code(0x7B)))
        XCTAssertEqual(try ChordParser.parse("CONTROL + Page_Up"), KeyChord(modifiers: [.ctrlKey], key: .code(0x74)))
        XCTAssertEqual(try ChordParser.parse("  SUPER+Equal "), KeyChord(modifiers: [.superKey], key: .code(0x18)))
        XCTAssertEqual(try ChordParser.parse("F13"), KeyChord(modifiers: [], key: .code(0x69)))
        XCTAssertEqual(try ChordParser.parse("SHIFT + Print"), KeyChord(modifiers: [.shiftKey], key: .code(0x69)))
        XCTAssertEqual(try ChordParser.parse("Caps_Lock"), KeyChord(modifiers: [], key: .code(0x39)))
        XCTAssertEqual(try ChordParser.parse("SUPER + 0x1B"), KeyChord(modifiers: [.superKey], key: .code(0x1B)))
    }

    func testParsesMouseScrollMediaAndTapChords() throws {
        XCTAssertEqual(try ChordParser.parse("SUPER + mouse:272"), KeyChord(modifiers: [.superKey], key: .mouseButton(272)))
        XCTAssertEqual(try ChordParser.parse("SUPER + mouse:right"), KeyChord(modifiers: [.superKey], key: .mouseButton(273)))
        XCTAssertEqual(try ChordParser.parse("SUPER + mouse_up"), KeyChord(modifiers: [.superKey], key: .scrollUp))
        XCTAssertEqual(try ChordParser.parse("SUPER + CTRL + mouse_down"), KeyChord(modifiers: [.superKey, .ctrlKey], key: .scrollDown))
        XCTAssertEqual(try ChordParser.parse("VolumeUp"), KeyChord(modifiers: [], key: .media(.volumeUp)))
        XCTAssertEqual(try ChordParser.parse("XF86AudioRaiseVolume"), KeyChord(modifiers: [], key: .media(.volumeUp)))
        XCTAssertEqual(try ChordParser.parse("XF86MonBrightnessDown"), KeyChord(modifiers: [], key: .media(.brightnessDown)))
        XCTAssertEqual(try ChordParser.parse("XF86AudioPrev"), KeyChord(modifiers: [], key: .media(.previous)))
        XCTAssertEqual(try ChordParser.parse("SUPER"), KeyChord.tap(.superKey))
        XCTAssertEqual(try ChordParser.parse("SUPER + SUPER_L"), KeyChord.tap(.superKey))
        XCTAssertEqual(try ChordParser.parse("SUPER_TAP"), KeyChord.tap(.superKey))
        XCTAssertEqual(try ChordParser.parse("ALT"), KeyChord.tap(.altKey))
        XCTAssertTrue(try ChordParser.parse("SUPER").isModifierTap)
    }

    func testChordParseErrors() {
        func reason(_ text: String) -> String? {
            do {
                _ = try ChordParser.parse(text)
                return nil
            } catch let error as ChordParseError {
                return error.reason
            } catch {
                return String(describing: error)
            }
        }
        XCTAssertEqual(reason(""), "empty chord")
        XCTAssertTrue(reason("SUPER + Foo")?.contains("unknown key \"Foo\"") == true)
        XCTAssertTrue(reason("SUPER + Lefft")?.contains("did you mean \"Left\"") == true)
        XCTAssertTrue(reason("SUPER + SUPER + A")?.contains("twice") == true)
        XCTAssertTrue(reason("SUPER + ALT")?.contains("exactly one modifier") == true)
        XCTAssertTrue(reason("SUPER + +")?.contains("empty token") == true)
        XCTAssertTrue(reason("SHIFT + SUPER_L")?.contains("cannot be combined") == true)
        XCTAssertTrue(reason("SUPER + mouse:nope")?.contains("mouse:272") == true)
        XCTAssertTrue(reason("SUPER + A + B")?.contains("extra key") == true)
    }

    func testKeymapNotationRoundTrips() throws {
        let chords: [KeyChord] = [
            KeyChord(modifiers: [.superKey, .ctrlKey, .altKey, .shiftKey], key: .code(0x35)),
            KeyChord(modifiers: [.superKey], key: .mouseButton(272)),
            KeyChord(modifiers: [.superKey, .altKey], key: .scrollUp),
            KeyChord(modifiers: [], key: .media(.play)),
            .tap(.superKey),
            KeyChord(modifiers: [.shiftKey], key: .code(0x69)),
        ]
        for chord in chords {
            XCTAssertEqual(try ChordParser.parse(ChordParser.keymapNotation(chord)), chord)
            XCTAssertEqual(try ChordParser.parse(ChordParser.linuxNotation(chord)), chord)
        }
        XCTAssertEqual(ChordParser.linuxNotation(.tap(.superKey)), "SUPER + SUPER_L")
        XCTAssertEqual(ChordParser.linuxNotation(KeyChord(modifiers: [.superKey], key: .code(0x74))), "SUPER + Page_Up")
        XCTAssertEqual(ChordParser.linuxNotation(KeyChord(modifiers: [], key: .media(.volumeUp))), "XF86AudioRaiseVolume")
    }

    func testMacNotation() throws {
        let a = ModifierMap.optionIsSuper
        XCTAssertEqual(ChordParser.format(try ChordParser.parse("SUPER + SHIFT + Left"), modifierMap: a), "⌥L ⇧ ←")
        XCTAssertEqual(ChordParser.format(try ChordParser.parse("CTRL + SUPER + Space"), modifierMap: a), "⌃ ⌥L Space")
        XCTAssertEqual(ChordParser.format(try ChordParser.parse("SUPER + ALT + L"), modifierMap: a), "⌥L ⌘L L")
        XCTAssertEqual(ChordParser.format(try ChordParser.parse("SUPER"), modifierMap: a), "⌥L tap")
        XCTAssertEqual(ChordParser.format(try ChordParser.parse("SUPER + Minus"), modifierMap: a), "⌥L -")
        XCTAssertEqual(ChordParser.format(try ChordParser.parse("SUPER + mouse:272"), modifierMap: a), "⌥L Left Click")
        XCTAssertEqual(ChordParser.format(try ChordParser.parse("VolumeUp"), modifierMap: a), "Volume Up")
        XCTAssertEqual(ChordParser.format(try ChordParser.parse("CTRL + SUPER + ALT + SHIFT + Escape"), modifierMap: a), "⌃ ⌥L ⇧ ⌘L ⎋")
        XCTAssertEqual(ChordParser.format(try ChordParser.parse("SUPER + Q"), modifierMap: .commandIsSuper), "⌘L Q")
        XCTAssertEqual(ChordParser.format(try ChordParser.parse("SUPER + 1"), modifierMap: .capsLockIsHyper), "⇪ 1")

        struct Norwegian: KeyboardLayoutCharacters {
            var layoutName: String { "Norwegian" }
            func character(forKeyCode code: UInt16, shift: Bool) -> String? { code == 0x1B ? "+" : code == 0x18 ? "´" : nil }
            func optionCharacter(forKeyCode code: UInt16, shift: Bool) -> String? { nil }
        }
        XCTAssertEqual(ChordParser.format(try ChordParser.parse("SUPER + Minus"), modifierMap: a, layout: Norwegian()), "⌥L +")
        XCTAssertEqual(ChordParser.format(try ChordParser.parse("SUPER + Equal"), modifierMap: a, layout: Norwegian()), "⌥L ´")
    }

    func testUSQwertyOptionCharacters() {
        let us = USQwertyCharacters()
        XCTAssertEqual(us.optionCharacter(forKeyCode: 0x0C), "œ")
        XCTAssertEqual(us.optionCharacter(forKeyCode: 0x0C, shift: true), "Œ")
        XCTAssertEqual(us.character(forKeyCode: 0x0C, shift: false), "q")
        XCTAssertEqual(us.character(forKeyCode: 0x0C, shift: true), "Q")
        XCTAssertNil(us.character(forKeyCode: 0x7B, shift: false))
    }

    // MARK: - Default keymap

    func testDefaultKeymapLoadsFromBundle() throws {
        let url = try XCTUnwrap(KeymapLoader.defaultKeymapURL)
        XCTAssertTrue(url.path.hasSuffix("Resources/keymap.default.toml"), url.path)
        XCTAssertNotNil(
            Bundle.module.url(forResource: "keymap.default", withExtension: "toml", subdirectory: "Resources"),
            "resources: [.copy(\"Resources\")] keeps the Resources/ subdirectory inside the bundle"
        )
        var warnings: [String] = []
        let keymap = try KeymapParser.parse(toml: try KeymapLoader.defaultKeymapText(), warnings: &warnings)
        XCTAssertEqual(warnings, [], "the shipped keymap must parse without warnings")
        XCTAssertEqual(keymap.modifiers, .optionIsSuper)
        XCTAssertGreaterThan(keymap.binds.count, 100)
        XCTAssertEqual(keymap.bind(id: "wm.panic"), KeymapParser.panicBind)
        XCTAssertEqual(KeymapLoader.loadDefault(), try KeymapLoader.loadDefaultOrThrow())
        for bind in keymap.binds {
            XCTAssertEqual(bind.keys.count, bind.chords.count, bind.id)
        }
    }

    func testDefaultKeymapHasUniqueChordsAndIDs() throws {
        let keymap = try KeymapLoader.loadDefaultOrThrow()
        let ids = keymap.binds.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        let duplicates = keymap.bindsByChord.filter { $0.value.count > 1 }
        XCTAssertTrue(duplicates.isEmpty, "duplicate chords: \(duplicates.map { "\($0.key): \($0.value.map(\.id))" })")
    }

    func testDefaultKeymapGestures() throws {
        let (_, extras) = try KeymapParser.parseWithExtras(toml: try KeymapLoader.defaultKeymapText())
        XCTAssertEqual(extras.gestures, GestureConfig(enabled: false, workspaceSwipeFingers: 4, specialFingers: 3, sleepFingers: 4))
    }

    func testDefaultKeymapSpotChecks() throws {
        let keymap = try KeymapLoader.loadDefaultOrThrow()
        let tap = try XCTUnwrap(keymap.bind(id: "launcher.tap"))
        XCTAssertEqual(tap.chords, [.tap(.superKey)])
        XCTAssertEqual(tap.flags, [.release])
        XCTAssertEqual(tap.linux, "SUPER + SUPER_L")
        XCTAssertEqual(keymap.bind(id: "launcher.toggle")?.flags, [])

        let ws10 = try XCTUnwrap(keymap.bind(id: "ws.focus.10"))
        XCTAssertEqual(ws10.action, Action(.workspaceFocus, index: 10))
        XCTAssertEqual(ws10.chords, [KeyChord(modifiers: [.superKey], key: .code(0x1D))])

        let group3 = try XCTUnwrap(keymap.bind(id: "ws.moveGroup.3"))
        XCTAssertEqual(group3.action, Action(.workspaceMoveGroup, group: 3))
        XCTAssertEqual(group3.chords, [KeyChord(modifiers: [.superKey, .ctrlKey, .altKey], key: .code(0x14))])

        let narrower = try XCTUnwrap(keymap.bind(id: "window.resize.narrower"))
        XCTAssertEqual(narrower.action.axis, .width)
        XCTAssertEqual(narrower.action.delta, -10)
        XCTAssertEqual(narrower.flags, [.repeat])
        XCTAssertTrue(narrower.description.contains("%"), "resize delta is documented as percent")

        XCTAssertEqual(keymap.bind(id: "ws.next")?.flags, [.repeat])
        XCTAssertEqual(keymap.bind(id: "ws.next.scroll")?.flags, [])
        XCTAssertEqual(keymap.bind(id: "window.drag")?.flags, [.mouse])
        XCTAssertEqual(keymap.bind(id: "audio.volumeUp")?.flags, [.repeat, .locked])
        XCTAssertEqual(keymap.bind(id: "audio.toggleMute")?.flags, [.locked])
        XCTAssertEqual(keymap.bind(id: "osd.capsLock")?.flags, [.locked, .release])
        XCTAssertEqual(keymap.bind(id: "osd.capsLock")?.action, Action(.osdLockKey, args: ["key": .string("caps")]))
        XCTAssertEqual(keymap.bind(id: "capture.full")?.flags, [.locked])
        XCTAssertEqual(keymap.bind(id: "capture.region")?.linux, "Print")
        XCTAssertNil(keymap.binds.first { $0.linux?.uppercased().contains("SUPER + SHIFT + ALT + S") == true }, "the stock region bind is replaced by Gabby's Print override")
        XCTAssertEqual(keymap.bind(id: "window.cycleNext")?.linux, "ALT + TAB")
        XCTAssertEqual(keymap.bind(id: "window.cycleNext")?.chords, [KeyChord(modifiers: [.superKey], key: .code(0x30))])
        XCTAssertEqual(keymap.bind(id: "special.sysmon")?.action, Action(.specialToggle, name: "sysmon"))
        XCTAssertEqual(keymap.bind(id: "session.menu")?.chords, [
            KeyChord(modifiers: [.ctrlKey, .altKey], key: .code(0x33)), KeyChord(modifiers: [.ctrlKey, .altKey], key: .code(0x75)),
        ])
    }

    // MARK: - Round trip

    func testDefaultKeymapRoundTrips() throws {
        let text = try KeymapLoader.defaultKeymapText()
        let (first, extras) = try KeymapParser.parseWithExtras(toml: text)
        let serialized = KeymapParser.serialize(first, extras: extras)
        var warnings: [String] = []
        let (second, secondExtras) = try KeymapParser.parseWithExtras(toml: serialized, warnings: &warnings)
        XCTAssertEqual(first, second)
        XCTAssertEqual(extras, secondExtras)
        XCTAssertEqual(warnings, [])
        XCTAssertEqual(KeymapParser.serialize(second, extras: secondExtras), serialized)
    }

    func testHandWrittenKeymapRoundTripsWithEscapesAndTypes() throws {
        let toml = """
            [modifiers]
            super = "lcmd"
            alt = "lopt"
            ctrl = "lctrl"
            shift = "shift"

            [[bind]]
            id = "a \\"quoted\\" id"
            keys = ["SUPER + 1", "SUPER + mouse_up"]
            action = "workspace.focus"
            args = { index = 3 }
            flags = ["repeat", "release"]
            linux = "SUPER + 1"
            description = "tab\\tand newline\\n and ünïcödé"
            enabled = false

            [[bind]]
            id = "exec"
            keys = ["CTRL + Return"]
            action = "exec"
            args = { cmd = "open -a \\"Safari\\"" }

            [[bind]]
            id = "resize"
            keys = ["SUPER + Equal"]
            action = "window.resize"
            args = { axis = "width", delta = 2.5 }

            [[bind]]
            id = "wm.panic"
            keys = ["CTRL + SUPER + ALT + SHIFT + Escape"]
            action = "wm.panic"
            """
        let first = try KeymapParser.parse(toml: toml)
        XCTAssertEqual(first.modifiers, ModifierMap(superKey: .lcmd, altKey: .lopt, ctrlKey: .lctrl, shiftKey: .shift))
        XCTAssertEqual(first.binds[0].enabled, false)
        XCTAssertEqual(first.binds[0].flags, [.repeat, .release])
        XCTAssertEqual(first.binds[0].description, "tab\tand newline\n and ünïcödé")
        XCTAssertEqual(first.binds[1].action.cmd, "open -a \"Safari\"")
        XCTAssertEqual(first.binds[2].action.args["delta"], .double(2.5))
        let second = try KeymapParser.parse(toml: KeymapParser.serialize(first))
        XCTAssertEqual(first, second)
    }

    // MARK: - Errors

    private func parseError(_ toml: String) -> KeymapError? {
        do {
            _ = try KeymapParser.parse(toml: toml)
            return nil
        } catch let error as KeymapError {
            return error
        } catch {
            XCTFail("unexpected error type \(error)")
            return nil
        }
    }

    private func bind(_ body: String, id: String = "t") -> String {
        """
        [modifiers]
        super = "lopt"

        [[bind]]
        id = "\(id)"
        \(body)
        """
    }

    func testErrorForBadAction() throws {
        let error = try XCTUnwrap(parseError(bind("keys = [\"SUPER + 1\"]\naction = \"workspace.focuss\"")))
        XCTAssertEqual(error.kind, .unknownAction)
        XCTAssertEqual(error.bindID, "t")
        XCTAssertEqual(error.line, 4)
        XCTAssertTrue(error.reason.contains("workspace.focuss"))
        XCTAssertTrue(error.reason.contains("workspace.focus"), error.reason)
        XCTAssertTrue(error.description.hasPrefix("keymap line 4, bind \"t\":"), error.description)
    }

    func testErrorForBadArgs() throws {
        let unknown = try XCTUnwrap(parseError(bind("keys = [\"SUPER + 1\"]\naction = \"workspace.focus\"\nargs = { idx = 1 }")))
        XCTAssertEqual(unknown.kind, .invalidArguments)
        XCTAssertTrue(unknown.reason.contains("no argument \"idx\""), unknown.reason)
        XCTAssertTrue(unknown.reason.contains("allowed: index"), unknown.reason)

        let missing = try XCTUnwrap(parseError(bind("keys = [\"SUPER + 1\"]\naction = \"workspace.focus\"")))
        XCTAssertEqual(missing.kind, .invalidArguments)
        XCTAssertTrue(missing.reason.contains("requires \"index\""), missing.reason)

        let wrongType = try XCTUnwrap(parseError(bind("keys = [\"SUPER + 1\"]\naction = \"workspace.focus\"\nargs = { index = \"one\" }")))
        XCTAssertEqual(wrongType.kind, .invalidArguments)
        XCTAssertTrue(wrongType.reason.contains("workspace number"), wrongType.reason)

        let direction = try XCTUnwrap(parseError(bind("keys = [\"SUPER + 1\"]\naction = \"window.focus\"\nargs = { direction = \"sideways\" }")))
        XCTAssertTrue(direction.reason.contains("left, right, up, down"), direction.reason)

        let extra = try XCTUnwrap(parseError(bind("keys = [\"SUPER + 1\"]\naction = \"lock\"\nargs = { index = 1 }")))
        XCTAssertTrue(extra.reason.contains("takes no arguments"), extra.reason)
    }

    func testErrorForBadFlagsKeysAndUnknownKeys() throws {
        let flag = try XCTUnwrap(parseError(bind("keys = [\"SUPER + 1\"]\naction = \"lock\"\nflags = [\"sticky\"]")))
        XCTAssertEqual(flag.kind, .invalidFlag)
        XCTAssertTrue(flag.reason.contains("release, repeat, locked, mouse"), flag.reason)

        let chord = try XCTUnwrap(parseError(bind("keys = [\"SUPER + Nope\"]\naction = \"lock\"")))
        XCTAssertEqual(chord.kind, .invalidChord)
        XCTAssertTrue(chord.reason.contains("unknown key \"Nope\""), chord.reason)

        let keysType = try XCTUnwrap(parseError(bind("keys = \"SUPER + 1\"\naction = \"lock\"")))
        XCTAssertEqual(keysType.kind, .structure)
        XCTAssertTrue(keysType.reason.contains("array"), keysType.reason)

        let unknownKey = try XCTUnwrap(parseError(bind("keys = [\"SUPER + 1\"]\naction = \"lock\"\ncolour = \"red\"")))
        XCTAssertEqual(unknownKey.kind, .unknownKey)
        XCTAssertTrue(unknownKey.reason.contains("\"colour\""), unknownKey.reason)
        XCTAssertTrue(unknownKey.reason.contains("allowed: id, keys, action"), unknownKey.reason)

        let topLevel = try XCTUnwrap(parseError("[modifiers]\nsuper = \"lopt\"\n\n[binds]\nx = 1\n"))
        XCTAssertEqual(topLevel.kind, .unknownKey)
        XCTAssertEqual(topLevel.line, 4)

        let modifier = try XCTUnwrap(parseError("[modifiers]\nsuper = \"hyper\"\n"))
        XCTAssertEqual(modifier.kind, .invalidValue)
        XCTAssertEqual(modifier.line, 2)
        XCTAssertTrue(modifier.reason.contains("lopt"), modifier.reason)

        let duplicate = try XCTUnwrap(parseError(bind("keys = [\"SUPER + 1\"]\naction = \"lock\"\n\n[[bind]]\nid = \"t\"\nkeys = [\"SUPER + 2\"]\naction = \"lock\"")))
        XCTAssertEqual(duplicate.kind, .duplicateID)
        XCTAssertEqual(duplicate.line, 9)
        XCTAssertEqual(duplicate.bindID, "t")

        let syntax = try XCTUnwrap(parseError("[modifiers\nsuper = \"lopt\"\n"))
        XCTAssertEqual(syntax.kind, .syntax)
        XCTAssertNotNil(syntax.line)

        let gestures = try XCTUnwrap(parseError("[gestures]\nenabled = true\nfingers = 3\n"))
        XCTAssertEqual(gestures.kind, .unknownKey)
        XCTAssertEqual(gestures.line, 3)
    }

    func testLinuxFieldIsValidated() throws {
        let error = try XCTUnwrap(parseError(bind("keys = [\"SUPER + 1\"]\naction = \"lock\"\nlinux = \"SUPER + Bogus\"")))
        XCTAssertEqual(error.kind, .invalidChord)
        XCTAssertTrue(error.reason.hasPrefix("linux:"), error.reason)
    }

    func testMouseChordWithoutMouseFlagWarns() throws {
        var warnings: [String] = []
        _ = try KeymapParser.parse(toml: bind("keys = [\"SUPER + mouse:272\"]\naction = \"window.drag\"", id: "d"), warnings: &warnings)
        XCTAssertTrue(warnings.contains { $0.contains("\"d\"") && $0.contains("mouse flag") }, "\(warnings)")
    }

    // MARK: - Panic chord

    func testPanicBindIsAddedWhenMissing() throws {
        var warnings: [String] = []
        let keymap = try KeymapParser.parse(toml: bind("keys = [\"SUPER + 1\"]\naction = \"lock\""), warnings: &warnings)
        XCTAssertEqual(keymap.binds.last, KeymapParser.panicBind)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("wm.panic"), warnings[0])
        XCTAssertEqual(keymap.bindsByChord[KeymapParser.panicBind.chords[0]]?.map(\.id), ["wm.panic"])
    }

    func testPanicBindIsRestoredWhenAltered() throws {
        let altered = """
            [[bind]]
            id = "wm.panic"
            keys = ["SUPER + Escape"]
            action = "lock"
            enabled = false
            """
        var warnings: [String] = []
        let keymap = try KeymapParser.parse(toml: altered, warnings: &warnings)
        XCTAssertEqual(keymap.binds, [KeymapParser.panicBind])
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("fixed"), warnings[0])
        XCTAssertTrue(warnings[0].contains("enabled = false"), warnings[0])
    }

    func testPanicBindUntouchedWhenCorrect() throws {
        var warnings: [String] = []
        let keymap = try KeymapParser.parse(toml: KeymapParser.serialize(Keymap(modifiers: .commandIsSuper, binds: [KeymapParser.panicBind])), warnings: &warnings)
        XCTAssertEqual(keymap.binds, [KeymapParser.panicBind])
        XCTAssertEqual(warnings, [])
    }

    // MARK: - Loader

    func testLoadFromFileAndUserFallback() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("caelestia-keymap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("keymap.toml")

        let (fallback, noWarnings) = KeymapLoader.loadUserOrDefault(userFile: file)
        XCTAssertEqual(fallback, KeymapLoader.loadDefault())
        XCTAssertEqual(noWarnings, [])

        try "[[bind]]\nid = \"x\"\nkeys = [\"SUPER + 1\"]\naction = \"lock\"\n".write(to: file, atomically: true, encoding: .utf8)
        let loaded = try KeymapLoader.load(from: file)
        XCTAssertEqual(loaded.binds.map(\.id), ["x", "wm.panic"])
        let (user, userWarnings) = KeymapLoader.loadUserOrDefault(userFile: file)
        XCTAssertEqual(user.binds.map(\.id), ["x", "wm.panic"])
        XCTAssertEqual(userWarnings.count, 1, "panic bind restore is reported: \(userWarnings)")

        try "this is not toml = = =".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try KeymapLoader.load(from: file)) { error in
            XCTAssertEqual((error as? KeymapError)?.kind, .syntax)
        }
        let (broken, brokenWarnings) = KeymapLoader.loadUserOrDefault(userFile: file)
        XCTAssertEqual(broken, KeymapLoader.loadDefault())
        XCTAssertEqual(brokenWarnings.count, 1)
        XCTAssertTrue(brokenWarnings[0].contains("using the default keymap"), brokenWarnings[0])

        XCTAssertThrowsError(try KeymapLoader.load(from: dir.appendingPathComponent("missing.toml"))) { error in
            XCTAssertEqual((error as? KeymapError)?.kind, .io)
        }
    }

    // MARK: - Watcher

    func testWatcherReloadsAfterWriteAndKeepsLastGoodOnError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("caelestia-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("keymap.toml")
        try "[[bind]]\nid = \"one\"\nkeys = [\"SUPER + 1\"]\naction = \"lock\"\n".write(to: file, atomically: true, encoding: .utf8)

        let initial = expectation(description: "initial load")
        let reloaded = expectation(description: "reload after write")
        let failed = expectation(description: "parse error reported")
        let box = ResultBox()
        let watcher = KeymapWatcher(
            url: file, debounce: 0.1,
            onChange: { keymap, _ in
                box.append(.success(keymap.binds.map(\.id)))
                if keymap.binds.map(\.id) == ["one", "wm.panic"] { initial.fulfill() }
                if keymap.binds.map(\.id) == ["two", "wm.panic"] { reloaded.fulfill() }
            },
            onError: { error in
                box.append(.failure(error))
                failed.fulfill()
            }
        )
        watcher.start()
        wait(for: [initial], timeout: 2)

        let written = Date()
        try "[[bind]]\nid = \"two\"\nkeys = [\"SUPER + 2\"]\naction = \"lock\"\n".write(to: file, atomically: true, encoding: .utf8)
        wait(for: [reloaded], timeout: 0.5)
        XCTAssertLessThan(Date().timeIntervalSince(written), 0.5)
        XCTAssertEqual(watcher.lastGood?.binds.map(\.id), ["two", "wm.panic"])

        try "[[bind]]\nid = \"broken\"\nkeys = [\"SUPER + Nope\"]\naction = \"lock\"\n".write(to: file, atomically: true, encoding: .utf8)
        wait(for: [failed], timeout: 1)
        XCTAssertEqual(watcher.lastGood?.binds.map(\.id), ["two", "wm.panic"], "the last good map is kept after a parse error")
        if case .failure(let error)? = box.results.last {
            XCTAssertEqual(error.kind, .invalidChord)
            XCTAssertEqual(error.bindID, "broken")
        } else {
            XCTFail("expected the parse error last, got \(box.results)")
        }
        watcher.stop()
    }

    func testWatcherDeliversFallbackWhenFileIsMissing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("caelestia-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("keymap.toml")
        let fallback = Keymap(modifiers: .optionIsSuper, binds: [KeymapParser.panicBind])

        let delivered = expectation(description: "fallback delivered")
        let created = expectation(description: "file created later is picked up")
        let watcher = KeymapWatcher(
            url: file, fallback: fallback,
            onChange: { keymap, warnings in
                if keymap == fallback, warnings.count == 1 { delivered.fulfill() }
                if keymap.binds.map(\.id) == ["later", "wm.panic"] { created.fulfill() }
            },
            onError: { error in XCTFail("unexpected error \(error)") }
        )
        watcher.start()
        wait(for: [delivered], timeout: 2)
        try "[[bind]]\nid = \"later\"\nkeys = [\"SUPER + 3\"]\naction = \"lock\"\n".write(to: file, atomically: true, encoding: .utf8)
        wait(for: [created], timeout: 1)
        watcher.stop()
    }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Result<[String], KeymapError>] = []

    var results: [Result<[String], KeymapError>] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ r: Result<[String], KeymapError>) {
        lock.lock()
        storage.append(r)
        lock.unlock()
    }
}
