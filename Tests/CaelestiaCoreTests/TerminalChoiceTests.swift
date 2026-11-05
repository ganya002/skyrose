import XCTest
@testable import CaelestiaCore

final class TerminalChoiceTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(TerminalChoice(config: "kitty"), .kitty)
        XCTAssertEqual(TerminalChoice(config: " Kitty "), .kitty)
        XCTAssertEqual(TerminalChoice(config: "net.kovidgoyal.kitty"), .kitty)
        XCTAssertEqual(TerminalChoice(config: "rex"), .rex)
        XCTAssertEqual(TerminalChoice(config: "com.superlogical.rex"), .rex)
        XCTAssertEqual(TerminalChoice(config: "com.apple.Terminal"), .app(bundleID: "com.apple.Terminal"))
        XCTAssertEqual(TerminalChoice(config: "open -a iTerm"), .command("open -a iTerm"))
        XCTAssertEqual(TerminalChoice(config: "wezterm start"), .command("wezterm start"))
        XCTAssertEqual(TerminalChoice(config: ""), .command("kitty"))
    }

    func testOpenArguments() {
        XCTAssertEqual(TerminalChoice.kitty.openArguments, ["-n", "-b", "net.kovidgoyal.kitty"])
        XCTAssertEqual(TerminalChoice.rex.openArguments, ["-b", "com.superlogical.rex"])
        XCTAssertEqual(TerminalChoice.app(bundleID: "com.apple.Terminal").openArguments, ["-b", "com.apple.Terminal"])
        XCTAssertNil(TerminalChoice.command("wezterm").openArguments)
        XCTAssertNil(TerminalChoice.command("wezterm").bundleID)
        XCTAssertEqual(TerminalChoice.rex.bundleID, TerminalChoice.rexBundleID)
    }

    func testConfigValueRoundTrip() {
        for c in [TerminalChoice.kitty, .rex, .app(bundleID: "com.apple.Terminal"), .command("wezterm start")] {
            XCTAssertEqual(TerminalChoice(config: c.configValue), c)
        }
    }

    func testLooksLikeBundleID() {
        XCTAssertTrue(TerminalChoice.looksLikeBundleID("com.apple.Terminal"))
        XCTAssertTrue(TerminalChoice.looksLikeBundleID("org.my-app_1.x"))
        XCTAssertFalse(TerminalChoice.looksLikeBundleID("kitty"))
        XCTAssertFalse(TerminalChoice.looksLikeBundleID("open -a iTerm.app"))
        XCTAssertFalse(TerminalChoice.looksLikeBundleID("/Applications/iTerm.app"))
        XCTAssertFalse(TerminalChoice.looksLikeBundleID(".hidden"))
        XCTAssertFalse(TerminalChoice.looksLikeBundleID("trailing."))
    }
}
