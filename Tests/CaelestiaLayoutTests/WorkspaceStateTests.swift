import XCTest
import CoreGraphics
import CaelestiaCore
@testable import CaelestiaLayout

/// Workspace model from spec 4.4 / 12.1: focus, move, move_silent, Caelestia group math, special
/// workspaces, specialWsCloseAny, focus_on_close, multi-display.
final class WorkspaceStateTests: XCTestCase {
    let env = LayoutEnvironment(areas: ["A": CGRect(x: 10, y: 10, width: 1450, height: 936)])

    func state(windows: [WindowID] = []) -> WorkspaceState {
        var s = WorkspaceState()
        s.ensureDisplay("A")
        for w in windows { s.addWindow(w, env: env) }
        return s
    }

    // MARK: Group math (10·(g−1)+n)

    func testGroupMath() {
        XCTAssertEqual(WorkspaceMath.number(n: 3, group: 1), 3)
        XCTAssertEqual(WorkspaceMath.number(n: 3, group: 2), 13)
        XCTAssertEqual(WorkspaceMath.number(n: 10, group: 5), 50)
        XCTAssertEqual(WorkspaceMath.group(of: 13), 2)
        XCTAssertEqual(WorkspaceMath.group(of: 10), 1)
        XCTAssertEqual(WorkspaceMath.indexInGroup(of: 13), 3)
        XCTAssertEqual(WorkspaceMath.indexInGroup(of: 20), 10)
    }

    func testWsactionFocusUsesTheCurrentGroup() {
        var s = state()
        XCTAssertEqual(s.focusWorkspace(index: 4, config: env.config), 4)
        XCTAssertEqual(s.focusWorkspaceGroup(2, config: env.config), 14, "same slot in group 2")
        XCTAssertEqual(s.focusWorkspace(index: 7, config: env.config), 17, "slot 7 of group 2")
        XCTAssertEqual(s.activeNumberedWorkspace(forDisplay: "A"), 17)
    }

    // MARK: Focus / move / move_silent

    func testNewDisplayStartsOnWorkspace1() {
        XCTAssertEqual(state().activeNumberedWorkspace(forDisplay: "A"), 1)
    }

    func testMoveFollowsAndMoveSilentStays() {
        var s = state(windows: [1, 2])
        XCTAssertTrue(s.moveWindow(2, toIndex: 3, follow: false, env: env))
        XCTAssertEqual(s.workspace(of: 2), .numbered(3))
        XCTAssertEqual(s.activeNumberedWorkspace(forDisplay: "A"), 1, "silent move keeps the workspace")
        XCTAssertEqual(s.focusedWindow, 1)

        XCTAssertTrue(s.moveWindow(1, toIndex: 3, follow: true, env: env))
        XCTAssertEqual(s.activeNumberedWorkspace(forDisplay: "A"), 3)
        XCTAssertEqual(s.focusedWindow, 1)
        XCTAssertNil(s[.numbered(1)], "the emptied, inactive workspace is dropped")
    }

    func testMoveToSameWorkspaceIsRefused() {
        var s = state(windows: [1])
        XCTAssertFalse(s.moveWindow(1, toIndex: 1, follow: true, env: env))
    }

    func testBarShowsFirstFivePlusOccupied() {
        var s = state(windows: [1])
        s.moveWindow(1, toIndex: 8, follow: false, env: env)
        XCTAssertEqual(s.occupiedWorkspaces(display: "A", shown: 5), [1, 2, 3, 4, 5, 8])
    }

    // MARK: Special workspaces

    func testSpecialToggleOpensAndCloses() {
        var s = state(windows: [1])
        var r = s.toggleSpecial(name: "special", generic: true, config: env.config)
        XCTAssertEqual(r.opened, "special")
        XCTAssertEqual(s.activeWorkspace(forDisplay: "A"), .special("special"))
        r = s.toggleSpecial(name: "special", generic: true, config: env.config)
        XCTAssertEqual(r.closed, "special")
        XCTAssertEqual(s.activeWorkspace(forDisplay: "A"), .numbered(1))
        XCTAssertEqual(s.focusedWindow, 1, "focus returns to the numbered workspace")
    }

    func testSpecialWsCloseAnyClosesWhicheverIsOpen() {
        var s = state()
        let r1 = s.toggleSpecial(name: "music", config: env.config)
        XCTAssertEqual(r1.opened, "music")
        XCTAssertTrue(r1.needsAppPlacement)
        let r2 = s.toggleSpecial(name: "special", generic: true, config: env.config)
        XCTAssertEqual(r2.closed, "music")
        XCTAssertNil(r2.opened)
        XCTAssertNil(s.openSpecial(onDisplay: "A"))
    }

    func testWithoutCloseAnyTheGenericToggleReplacesTheNamedSpecial() {
        var s = state()
        var config = env.config
        config.specialWsCloseAny = false
        s.toggleSpecial(name: "music", config: config)
        let r = s.toggleSpecial(name: "special", generic: true, config: config)
        XCTAssertEqual(r.opened, "special")
        XCTAssertEqual(s.openSpecial(onDisplay: "A"), "special")
    }

    func testNamedSpecialReplacesAnother() {
        var s = state()
        s.toggleSpecial(name: "music", config: env.config)
        let r = s.toggleSpecial(name: "sysmon", config: env.config)
        XCTAssertEqual(r.closed, "music")
        XCTAssertEqual(r.opened, "sysmon")
    }

    func testSwitchingNumberedWorkspaceKeepsSpecialOpen() {
        var s = state(windows: [1])
        s.moveToSpecial(1, env: env)
        XCTAssertEqual(s.openSpecial(onDisplay: "A"), "special")
        s.focusWorkspace(.numbered(2))
        XCTAssertEqual(s.openSpecial(onDisplay: "A"), "special")
        XCTAssertEqual(s.activeNumberedWorkspace(forDisplay: "A"), 2)
    }

    func testMoveOutOfSpecialClosesIt() {
        var s = state(windows: [1])
        s.moveToSpecial(1, env: env)
        XCTAssertTrue(s.moveOutOfSpecial(1, env: env))
        XCTAssertNil(s.openSpecial(onDisplay: "A"))
        XCTAssertEqual(s.workspace(of: 1), .numbered(1))
    }

    // MARK: focus_on_close = 1

    func testCloseFocusesWindowUnderCursorFirst() {
        var s = state(windows: [1, 2, 3])
        XCTAssertEqual(s.closeWindow(3, cursorWindow: 1), 1)
    }

    func testCloseFallsBackToFocusHistory() {
        var s = state(windows: [1, 2, 3])
        s.recordFocus(1)
        s.recordFocus(3)
        XCTAssertEqual(s.closeWindow(3), 1, "1 was focused before 3")
    }

    func testClosingLastWindowLeavesNoFocus() {
        var s = state(windows: [1])
        XCTAssertNil(s.closeWindow(1))
        XCTAssertNil(s.focusedWindow)
    }

    // MARK: Floating / fullscreen / pin

    func testFloatingRoundTripRemembersFrame() {
        var s = state(windows: [1, 2])
        let rect = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertTrue(s.setFloating(1, true, frame: rect, env: env))
        XCTAssertEqual(s[.numbered(1)]?.floating[1], rect)
        XCTAssertTrue(s.setFloating(1, false, env: env))
        XCTAssertTrue(s.toggleFloating(1, env: env))
        // Hyprland re-floats at the remembered *size*, centred on the window's tile (ops21).
        XCTAssertEqual(s[.numbered(1)]?.floating[1]?.size, rect.size, "last floating size is reused")
    }

    func testPinRequiresFloating() {
        var s = state(windows: [1])
        XCTAssertFalse(s.setPinned(1, true))
        s.setFloating(1, true, env: env)
        XCTAssertTrue(s.setPinned(1, true))
        XCTAssertTrue(s.isPinned(1))
    }

    func testOnlyOneFullscreenPerWorkspace() {
        var s = state(windows: [1, 2])
        XCTAssertTrue(s.toggleFullscreen(1))
        s.recordFocus(2, unfullscreenOthers: true)
        XCTAssertNil(s[.numbered(1)]?.fullscreen, "on_focus_under_fullscreen = 2")
    }

    // MARK: Displays

    func testSecondDisplayGetsNextFreeWorkspaceAndUnplugKeepsNumbers() {
        var s = state(windows: [1])
        XCTAssertEqual(s.ensureDisplay("B"), 2)
        s.addWindow(2, to: .numbered(2), env: env)
        s.removeDisplay("B", movingTo: "A")
        XCTAssertEqual(s.workspace(of: 2), .numbered(2))
        XCTAssertEqual(s.display(of: 2), "A")
        XCTAssertEqual(s.displays, ["A"])
    }

    func testStateIsCodableForTheJournal() throws {
        var s = state(windows: [1, 2, 3])
        s.toggleSpecial(name: "music", config: env.config)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceState.self, from: data), s)
    }
}
