import Carbon.HIToolbox
import XCTest
import CaelestiaCore
@testable import CaelestiaPlatform

final class SecureInputHotkeysTests: XCTestCase {
    func testDefaultKeymapKeepsWorkspaceBindsAsOptionHotKeys() throws {
        let entries = SecureInputHotkeys.entries(for: try KeymapLoader.loadDefaultOrThrow())
        let ws1 = try XCTUnwrap(entries.first { $0.bind.id == "ws.focus.1" })
        XCTAssertEqual(ws1.code, UInt32(kVK_ANSI_1))
        XCTAssertEqual(ws1.carbonModifiers, UInt32(optionKey))
        // Never a bare key (it would steal typing), and every key + modifier pair once.
        XCTAssertFalse(entries.contains { $0.carbonModifiers == 0 })
        XCTAssertEqual(Set(entries.map { [$0.code, $0.carbonModifiers] }).count, entries.count)
    }

    func testSkipsCapsLockModifier() throws {
        let toml = """
            [modifiers]
            super = "capslock"
            alt = "lopt"
            ctrl = "ctrl"
            shift = "shift"
            [[bind]]
            id = "a"
            keys = ["SUPER + 1"]
            action = "workspace.focus"
            args = { index = 1 }
            [[bind]]
            id = "b"
            keys = ["ALT + 2"]
            action = "workspace.focus"
            args = { index = 2 }
            """
        XCTAssertEqual(SecureInputHotkeys.entries(for: try KeymapParser.parse(toml: toml)).map(\.bind.id), ["b"])
    }
}
