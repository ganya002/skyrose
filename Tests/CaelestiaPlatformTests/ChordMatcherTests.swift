import XCTest
import CaelestiaCore
@testable import CaelestiaPlatform

/// Hotkey decisions from spec 3.1 / 10.10 with the shipped keymap (preset A: Super = ⌥L): left vs
/// right Option, the Super tap, secure input, the lock screen and the panic chord.
final class ChordMatcherTests: XCTestCase {
    // CGEventFlags family masks + NX_DEVICE* side bits.
    let lopt: UInt64 = 0x80000 | 0x20
    let ropt: UInt64 = 0x80000 | 0x40
    let lcmd: UInt64 = 0x100000 | 0x08
    let ctrl: UInt64 = 0x40000 | 0x01
    let shift: UInt64 = 0x20000 | 0x02

    let optLCode: UInt16 = 0x3A
    let key1: UInt16 = 0x12
    let keyQ: UInt16 = 0x0C
    let escape: UInt16 = 0x35

    var matcher: ChordMatcher!

    override func setUpWithError() throws {
        matcher = ChordMatcher(keymap: try KeymapLoader.loadDefaultOrThrow())
    }

    func ids(_ d: MatchDecision) -> [String] { d.fired.map(\.bind.id) }

    func testLeftOptionPlus1FocusesWorkspace1() {
        _ = matcher.handle(.flagsChanged(code: optLCode, flags: lopt), now: 0)
        let d = matcher.handle(.keyDown(code: key1, flags: lopt, isRepeat: false), now: 0.05)
        XCTAssertEqual(ids(d), ["ws.focus.1"])
        XCTAssertTrue(d.swallows)
    }

    func testRightOptionStillTypesCharacters() {
        _ = matcher.handle(.flagsChanged(code: 0x3D, flags: ropt), now: 0)
        let d = matcher.handle(.keyDown(code: key1, flags: ropt, isRepeat: false), now: 0.05)
        XCTAssertEqual(d, .passThrough)
    }

    func testModifierChangesAreNeverSwallowed() {
        XCTAssertFalse(matcher.handle(.flagsChanged(code: optLCode, flags: lopt), now: 0).swallows)
    }

    // MARK: Super tap

    func testSuperTapWithinWindowOpensLauncher() {
        _ = matcher.handle(.flagsChanged(code: optLCode, flags: lopt), now: 0)
        let d = matcher.handle(.flagsChanged(code: optLCode, flags: 0), now: 0.2)
        XCTAssertEqual(ids(d), ["launcher.tap"])
    }

    func testSlowSuperReleaseIsNotATap() {
        _ = matcher.handle(.flagsChanged(code: optLCode, flags: lopt), now: 0)
        XCTAssertEqual(ids(matcher.handle(.flagsChanged(code: optLCode, flags: 0), now: 0.4)), [])
    }

    func testTypingAnOptionCharacterCancelsTheTap() {
        _ = matcher.handle(.flagsChanged(code: optLCode, flags: lopt), now: 0)
        _ = matcher.handle(.keyDown(code: keyQ, flags: lopt, isRepeat: false), now: 0.05)
        _ = matcher.handle(.keyUp(code: keyQ, flags: lopt), now: 0.08)
        XCTAssertEqual(ids(matcher.handle(.flagsChanged(code: optLCode, flags: 0), now: 0.1)), [])
    }

    func testOptionClickCancelsTheTap() {
        let p = CGPoint(x: 10, y: 10)
        _ = matcher.handle(.flagsChanged(code: optLCode, flags: lopt), now: 0)
        _ = matcher.handle(.mouseDown(button: MouseButtonCode.left, flags: lopt, location: p), now: 0.05)
        _ = matcher.handle(.mouseUp(button: MouseButtonCode.left, flags: lopt, location: p), now: 0.08)
        XCTAssertEqual(ids(matcher.handle(.flagsChanged(code: optLCode, flags: 0), now: 0.1)), [])
    }

    func testTapWindowIsConfigurable() {
        var input = InputConfig()
        input.superTapMs = 500
        matcher.update(input: input)
        _ = matcher.handle(.flagsChanged(code: optLCode, flags: lopt), now: 0)
        XCTAssertEqual(ids(matcher.handle(.flagsChanged(code: optLCode, flags: 0), now: 0.45)), ["launcher.tap"])
    }

    // MARK: Safety

    func testPanicChordFiresEvenWithAnEmptyKeymap() throws {
        let empty = ChordMatcher(keymap: try KeymapParser.parse(toml: ""))
        let all = ctrl | lopt | lcmd | shift
        let d = empty.handle(.keyDown(code: escape, flags: all, isRepeat: false), now: 0)
        XCTAssertEqual(ids(d), [ChordMatcher.panicBind.id])
    }

    func testSecureInputPassesHotkeysButNotPanic() {
        matcher.secureInputActive = true
        XCTAssertEqual(matcher.handle(.keyDown(code: key1, flags: lopt, isRepeat: false), now: 0), .passThrough)
        let all = ctrl | lopt | lcmd | shift
        XCTAssertEqual(ids(matcher.handle(.keyDown(code: escape, flags: all, isRepeat: false), now: 0.1)), [ChordMatcher.panicBind.id])
    }

    func testLockScreenPassesWorkspaceBinds() {
        matcher.isLocked = true
        XCTAssertEqual(matcher.handle(.keyDown(code: key1, flags: lopt, isRepeat: false), now: 0), .passThrough)
    }

    func testHotReloadAppliesToTheNextEvent() throws {
        let toml = """
            [modifiers]
            super = "lcmd"
            alt = "lopt"
            ctrl = "ctrl"
            shift = "shift"
            [[bind]]
            id = "ws.focus.1"
            keys = ["SUPER + 1"]
            action = "workspace.focus"
            args = { index = 1 }
            """
        matcher.update(keymap: try KeymapParser.parse(toml: toml))
        XCTAssertEqual(matcher.handle(.keyDown(code: key1, flags: lopt, isRepeat: false), now: 0), .passThrough)
        XCTAssertEqual(ids(matcher.handle(.keyDown(code: key1, flags: lcmd, isRepeat: false), now: 0.1)), ["ws.focus.1"])
    }
}
