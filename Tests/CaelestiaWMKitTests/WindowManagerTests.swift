import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CaelestiaPlatform
import XCTest
@testable import CaelestiaWMKit

/// End-to-end tiling through the WM with fake windows/displays: discovery, dwindle, workspaces,
/// special workspaces, binds through the real hotkey engine, rules, IPC and display changes.
@MainActor
final class WindowManagerTests: XCTestCase {
    // MARK: Discovery + dwindle

    func testExistingWindowsTileWithTheGoldenUltrawideNumbers() {
        let h = Harness(displays: [TestDisplays.ultrawide])
        let a = h.system.existing("left")
        let b = h.system.existing("right")
        h.start()
        // clients.json: (21,21,2533x1398) and (2566,21,2533x1398); the bar auto-hides (shell.json).
        XCTAssertEqual(h.frame(a), CGRect(x: 21, y: 21, width: 2533, height: 1398))
        XCTAssertEqual(h.frame(b), CGRect(x: 2566, y: 21, width: 2533, height: 1398))
        XCTAssertEqual(h.wm.borderFrames[a.windowID], CGRect(x: 20, y: 20, width: 2535, height: 1400))
    }

    func testSingleWindowGetsTwentyPointGapsBelowTheMenuBar() {
        let h = Harness()
        let a = h.system.existing("only")
        h.start()
        // 10 frame + 20 single-window gap + 1 border; the menu bar takes 33 at the top.
        XCTAssertEqual(h.frame(a), CGRect(x: 31, y: 33 + 31, width: 1470 - 62, height: 956 - 33 - 62))
    }

    func testNewWindowSplitsTheFocusedOneAndTakesFocus() {
        let h = Harness()
        let a = h.system.existing("a")
        h.start()
        let b = h.system.open("b")
        h.settle()
        XCTAssertEqual(h.wm.state.focusedWindow, b.windowID)
        XCTAssertEqual(h.system.focusedWindowID, b.windowID)
        XCTAssertLessThan(h.frame(a).maxX, h.frame(b).minX, "side by side on a wide slot")
        let c = h.system.open("c")
        h.settle()
        // c splits b's slot (taller than wide), so b and c stack in the right half.
        XCTAssertEqual(h.frame(c).minX, h.frame(b).minX)
        XCTAssertLessThan(h.frame(b).maxY, h.frame(c).minY)
    }

    // MARK: Workspaces + parking

    func testWorkspaceSwitchParksAndRestoresExactFrames() throws {
        let h = Harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        let frameA = h.frame(a)
        let frameB = h.frame(b)

        XCTAssertEqual(h.press("2", Harness.lopt), ["ws.focus.2"])
        XCTAssertEqual(h.wm.state.activeNumberedWorkspace(forDisplay: "air"), 2)
        XCTAssertFalse(h.isOnScreen(a))
        XCTAssertFalse(h.isOnScreen(b))
        XCTAssertEqual(Set(h.journal.records().map(\.windowID)), [a.windowID, b.windowID])
        XCTAssertEqual(h.journal.record(for: a.windowID)?.restoreFrame, frameA)

        h.press("1", Harness.lopt)
        XCTAssertEqual(h.frame(a), frameA)
        XCTAssertEqual(h.frame(b), frameB)
        XCTAssertTrue(h.journal.records().isEmpty)
    }

    func testMoveToWorkspaceFollowAndSilent() {
        let h = Harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        h.wm.state.recordFocus(b.windowID)
        // ⌥L⇧3: move silently; focus stays on workspace 1 with a.
        h.press("3", Harness.lopt | Harness.shift)
        XCTAssertEqual(h.wm.state.workspace(of: b.windowID), .numbered(3))
        XCTAssertEqual(h.wm.state.activeNumberedWorkspace(forDisplay: "air"), 1)
        XCTAssertFalse(h.isOnScreen(b))
        XCTAssertEqual(h.wm.state.focusedWindow, a.windowID)
        // ⌥L⌘4 on a: move and follow.
        h.press("4", Harness.lopt | Harness.lcmd)
        XCTAssertEqual(h.wm.state.activeNumberedWorkspace(forDisplay: "air"), 4)
        XCTAssertTrue(h.isOnScreen(a))
        XCTAssertEqual(h.wm.state.focusedWindow, a.windowID)
    }

    func testWorkspacesOneToTen() {
        let h = Harness()
        h.system.existing("a")
        h.start()
        for (key, n) in [("1", 1), ("2", 2), ("3", 3), ("4", 4), ("5", 5), ("6", 6), ("7", 7), ("8", 8), ("9", 9), ("0", 10)] {
            h.press(key, Harness.lopt)
            XCTAssertEqual(h.wm.state.activeNumberedWorkspace(forDisplay: "air"), n, "⌥L+\(key)")
        }
    }

    func testSpecialWorkspaceToggleShowsAndHidesIt() {
        let h = Harness()
        let a = h.system.existing("a")
        let s = h.system.existing("scratch")
        h.start()
        h.wm.state.recordFocus(s.windowID)
        h.press("S", Harness.lopt | Harness.lcmd)  // ⌥L⌘S → move to special (and show it)
        XCTAssertEqual(h.wm.state.workspace(of: s.windowID), .special("special"))
        XCTAssertEqual(h.wm.state.openSpecial(onDisplay: "air"), "special")
        XCTAssertTrue(h.isOnScreen(s))
        XCTAssertGreaterThan(s.raiseCount, 0, "special windows are raised above the workspace")

        h.press("S", Harness.lopt)  // ⌥L+S hides it
        XCTAssertNil(h.wm.state.openSpecial(onDisplay: "air"))
        XCTAssertFalse(h.isOnScreen(s))
        XCTAssertTrue(h.isOnScreen(a))

        h.press("S", Harness.lopt)  // and shows it again
        XCTAssertTrue(h.isOnScreen(s))
        XCTAssertEqual(h.wm.state.focusedWindow, s.windowID)
    }

    // MARK: Focus / move / resize binds

    func testFocusSwapAndResizeBinds() {
        let h = Harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        h.wm.state.recordFocus(a.windowID)
        h.settle()

        XCTAssertEqual(h.press("Right", Harness.lopt), ["window.focus.right"])
        XCTAssertEqual(h.wm.state.focusedWindow, b.windowID)
        XCTAssertEqual(h.system.focusedWindowID, b.windowID)

        let leftSlot = h.frame(a)
        h.press("Left", Harness.lopt | Harness.shift)  // swap b to the left
        XCTAssertEqual(h.frame(b), leftSlot)

        let before = h.frame(b).width
        h.press("Equal", Harness.lopt)  // 10% wider
        XCTAssertEqual(h.frame(b).width, before + (before * 0.1).rounded(), accuracy: 2)
        XCTAssertEqual(h.frame(a).minX - h.frame(b).maxX, 12, accuracy: 0.5, "gap stays 10 + 2 borders")
    }

    func testToggleFloatAndFullscreenBinds() {
        let h = Harness()
        let a = h.system.existing("a")
        h.system.existing("b")
        h.start()
        h.wm.state.recordFocus(a.windowID)
        h.wm.perform(Action(.windowToggleFloat))
        h.settle()
        XCTAssertTrue(h.wm.isFloating(a.windowID))
        h.wm.perform(Action(.windowFullscreen))
        h.settle()
        XCTAssertEqual(h.frame(a), TestDisplays.air.frame)
        XCTAssertNil(h.wm.borderFrames[a.windowID], "no border on true fullscreen")
    }

    func testClosingTheFocusedWindowFocusesTheWindowUnderTheCursorThenHistory() {
        let h = Harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        let c = h.system.existing("c")
        h.start()
        for w in [a, b, c] { h.wm.state.recordFocus(w.windowID) }
        h.settle()
        h.system.underCursor = a.windowID
        h.press("Q", Harness.lopt)  // killactive
        XCTAssertNil(h.system.windows[c.windowID])
        XCTAssertEqual(h.wm.state.focusedWindow, a.windowID)
        h.system.underCursor = nil
        h.wm.perform(Action(.windowClose))
        h.settle()
        XCTAssertEqual(h.wm.state.focusedWindow, b.windowID, "next in focus history")
    }

    /// macOS focusing a parked window (⌘Tab, Dock click) switches to its workspace, except right
    /// after we parked it: then it is macOS handing focus to a sibling window, and following it
    /// would bounce straight back to the old workspace.
    func testFocusingAParkedWindowSwitchesWorkspaceOutsideTheGuard() {
        let h = Harness()
        let a = h.system.existing("a")
        h.start()
        h.press("2", Harness.lopt)
        XCTAssertTrue(h.wm.isParked(a.windowID))

        h.system.queue(.focused(a.windowID))  // within the guard
        h.settle()
        XCTAssertEqual(h.wm.state.activeNumberedWorkspace(forDisplay: "air"), 2)

        h.clock.now.addTimeInterval(1)
        h.system.queue(.focused(a.windowID))  // the user ⌘Tabs to it later
        h.settle()
        XCTAssertEqual(h.wm.state.activeNumberedWorkspace(forDisplay: "air"), 1)
        XCTAssertTrue(h.isOnScreen(a))
    }

    func testMinimizeAndRestoreRetile() {
        let h = Harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        let early = h.system.existing("minimized before start")
        early.isMinimized = true
        h.start()
        XCTAssertFalse(h.wm.isManaged(early.windowID))
        let half = h.frame(a)

        b.isMinimized = true
        h.system.queue(.minimized(b.windowID))
        h.settle()
        XCTAssertFalse(h.wm.isManaged(b.windowID))
        XCTAssertGreaterThan(h.frame(a).width, half.width, "a takes the whole area")

        b.isMinimized = false
        h.system.queue(.deminiaturized(b.windowID))
        early.isMinimized = false
        h.system.queue(.deminiaturized(early.windowID))
        h.settle()
        XCTAssertTrue(h.wm.isManaged(b.windowID))
        XCTAssertTrue(h.wm.isManaged(early.windowID))
        XCTAssertEqual(h.wm.state.windows(on: .numbered(1)).count, 3)
    }

    // MARK: Rules

    func testDialogsAndFixedSizeWindowsFloatCentredAndPopupsAreIgnored() {
        let h = Harness()
        h.system.existing("main")
        h.start()
        let dialog = h.system.open("Open File") { $0.subrole = "AXDialog"; $0.frame.size = CGSize(width: 400, height: 300) }
        let fixed = h.system.open("About") { $0.isResizable = false; $0.frame.size = CGSize(width: 300, height: 200) }
        let sheet = h.system.open("sheet") { $0.role = "AXSheet" }
        h.settle()
        let area = h.wm.usableArea(of: TestDisplays.air)
        XCTAssertTrue(h.wm.isFloating(dialog.windowID))
        XCTAssertTrue(h.wm.isFloating(fixed.windowID))
        XCTAssertEqual(h.frame(fixed).midX, area.midX, accuracy: 1)
        XCTAssertEqual(h.frame(fixed).midY, area.midY, accuracy: 1)
        XCTAssertFalse(h.wm.isManaged(sheet.windowID))
    }

    func testRuleSendsMusicAppToItsSpecialWorkspace() {
        let h = Harness()
        h.system.existing("main")
        h.start()
        let spotify = h.system.open("Spotify", bundle: "com.spotify.client", pid: 600)
        h.settle()
        XCTAssertEqual(h.wm.state.workspace(of: spotify.windowID), .special("music"))
        XCTAssertFalse(h.isOnScreen(spotify), "the special is closed, so the window is parked")
        h.wm.perform(Action(.specialToggle, name: "music"))
        h.settle()
        XCTAssertTrue(h.isOnScreen(spotify))
    }

    // MARK: Displays

    func testUnpluggingADisplayMovesItsWindowsOnScreen() {
        let h = Harness(displays: [TestDisplays.air, TestDisplays.external])
        let onAir = h.system.existing("air")
        let onExt = h.system.existing("ext", frame: CGRect(x: 2000, y: 200, width: 800, height: 600))
        h.start()
        XCTAssertEqual(h.wm.state.display(of: onExt.windowID), "ext")
        XCTAssertTrue(TestDisplays.external.frame.contains(h.frame(onExt)))

        h.screens.change(to: [TestDisplays.air])
        h.settle()
        XCTAssertEqual(h.wm.state.display(of: onExt.windowID), "air")
        XCTAssertTrue(h.isOnScreen(onAir))
        // Hyprland keeps the moved workspace's number; it is no longer visible on the Air, so the
        // window is parked on the Air (never left on the vanished display).
        if h.wm.state.isVisible(h.wm.state.workspace(of: onExt.windowID)!) {
            XCTAssertTrue(h.isOnScreen(onExt))
        } else {
            XCTAssertTrue(h.wm.isParked(onExt.windowID))
            XCTAssertTrue(TestDisplays.air.frame.intersects(h.frame(onExt)))
        }
    }

    func testFocusCrossesToTheNeighbouringDisplay() {
        let h = Harness(displays: [TestDisplays.air, TestDisplays.external])
        let onAir = h.system.existing("air")
        let onExt = h.system.existing("ext", frame: CGRect(x: 2000, y: 200, width: 800, height: 600))
        h.start()
        h.wm.state.recordFocus(onAir.windowID)
        h.settle()
        h.press("Right", Harness.lopt)
        XCTAssertEqual(h.wm.state.focusedWindow, onExt.windowID)
        XCTAssertEqual(h.wm.state.focusedDisplay, "ext")
    }

    // MARK: IPC

    func testIPCQueriesAndCommands() throws {
        let h = Harness(displays: [TestDisplays.ultrawide])
        let a = h.system.existing("left")
        h.system.existing("right")
        h.start()

        let (windows, _) = h.wm.respond(to: IPCRequest(.queryWindows))
        let entries = try XCTUnwrap(windows.result).decode([WindowQueryEntry].self)
        let left = try XCTUnwrap(entries.first { $0.title == "left" })
        XCTAssertEqual(left.at, [21, 21])
        XCTAssertEqual(left.size, [2533, 1398])
        XCTAssertEqual(left.workspace, WorkspaceRef(id: 1, name: "1"))

        XCTAssertTrue(h.wm.respond(to: IPCRequest(.wsFocus, args: ["index": 7])).response.ok)
        h.settle()
        XCTAssertEqual(h.wm.state.activeNumberedWorkspace(forDisplay: "uw"), 7)
        XCTAssertFalse(h.isOnScreen(a))

        let monitors = try XCTUnwrap(h.wm.respond(to: IPCRequest(.queryMonitors)).response.result).decode([MonitorQueryEntry].self)
        XCTAssertEqual(monitors.first?.reserved, [10, 10, 10, 10])
        XCTAssertEqual(monitors.first?.activeWorkspace.id, 7)

        // restoreAll brings parked windows back without quitting.
        XCTAssertTrue(h.wm.respond(to: IPCRequest(.wmRestoreAll)).response.ok)
        h.settle()
        XCTAssertTrue(h.isOnScreen(a))
        XCTAssertTrue(h.wm.isManaging)
        XCTAssertTrue(h.journal.records().isEmpty)

        let state = try XCTUnwrap(h.wm.respond(to: IPCRequest(.queryState)).response.result).decode(StateQueryEntry.self)
        XCTAssertEqual(state.windowCount, 2)
        XCTAssertNotNil(state.counters["layoutPasses"])

        XCTAssertFalse(h.wm.respond(to: IPCRequest(.shellLauncher)).response.ok, "no shell in this build")
    }

    func testBarDefaultMatchesArchShellJSON() {
        XCTAssertFalse(Config().bar.persistent)
        var c = Config()
        c.bar.persistent = true
        let h = Harness(config: c)
        XCTAssertEqual(h.wm.usableArea(of: TestDisplays.air).minX, 60, "max(frame, bar), not the sum")
    }
}
