import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CaelestiaPlatform
import XCTest
@testable import CaelestiaWMKit

/// The WM side of the native shell: reserved bar space, the workspace pills, the IPC hook and the
/// layout callback. Never constructs a ShellController / ShellBridge (those start system monitors).
@MainActor
final class ShellIntegrationTests: XCTestCase {
    private var air: DisplayInfo { TestDisplays.air }

    // MARK: usableArea

    func testAutoHideBarNotRevealedReservesOnlyTheFrame() {
        let h = Harness()
        XCTAssertFalse(h.wm.config.bar.persistent)
        XCTAssertEqual(h.wm.usableArea(of: air).minX, 10)
        XCTAssertEqual(h.wm.usableArea(of: air).minX, air.usableArea(reserved: .uniform(10)).minX)
    }

    func testRevealedAutoHideBarReservesNothing() {
        let h = Harness()
        h.wm.setBarRevealed(true, display: "air")
        XCTAssertEqual(h.wm.usableArea(of: air).minX, 10, "the bar overlays windows")
        XCTAssertEqual(h.wm.usableArea(of: air).maxX, 1470 - 10)
        h.wm.setBarRevealed(false, display: "air")
        XCTAssertEqual(h.wm.usableArea(of: air).minX, 10)
    }

    func testRevealOnAnotherDisplayDoesNotAffectThisOne() {
        let h = Harness(displays: [TestDisplays.air, TestDisplays.external])
        h.wm.setBarRevealed(true, display: "ext")
        XCTAssertEqual(h.wm.usableArea(of: TestDisplays.air).minX, 10)
        XCTAssertEqual(h.wm.usableArea(of: TestDisplays.external).minX, TestDisplays.external.frame.minX + 10)
    }

    func testPersistentBarReservesRegardlessOfReveal() {
        var config = Config()
        config.bar.persistent = true
        let h = Harness(config: config)
        XCTAssertEqual(h.wm.usableArea(of: air).minX, 60)
        h.wm.setBarRevealed(true, display: "air")
        XCTAssertEqual(h.wm.usableArea(of: air).minX, 60)
        h.wm.setBarRevealed(false, display: "air")
        XCTAssertEqual(h.wm.usableArea(of: air).minX, 60)
    }

    func testDisabledBarReservesNothingExtra() {
        var config = Config()
        config.bar.enabled = false
        let h = Harness(config: config)
        h.wm.setBarRevealed(true, display: "air")
        XCTAssertEqual(h.wm.usableArea(of: air).minX, 10)
    }

    func testRevealAndHideNeverRetileOrMoveWindows() {
        let h = Harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        let before = [h.frame(a), h.frame(b)]
        for revealed in [true, false, true, true, false] {
            h.wm.setBarRevealed(revealed, display: "air")
            XCTAssertFalse(h.wm.needsLayout)
            XCTAssertEqual(h.settle(), 0)
            XCTAssertEqual([h.frame(a), h.frame(b)], before)
        }
    }

    func testPersistentRevealSchedulesNoLayout() {
        var config = Config()
        config.bar.persistent = true
        let h = Harness(config: config)
        h.system.existing("a")
        h.start()
        h.wm.setBarRevealed(true, display: "air")
        XCTAssertFalse(h.wm.needsLayout)
        h.wm.setBarRevealed(false, display: "air")
        XCTAssertFalse(h.wm.needsLayout)
    }

    // MARK: ShellBridge.pills

    func testPillsShowFiveWorkspacesOfTheActiveGroup() {
        let h = Harness()
        h.system.existing("a")
        h.start()
        h.wm.state.focusWorkspace(.numbered(7))
        h.system.open("on seven")
        h.settle()
        let pills = ShellBridge.pills(state: h.wm.state, display: "air", shown: 5)
        XCTAssertEqual(pills.map(\.id), Array(6...10))
        XCTAssertEqual(pills.map(\.name), ["6", "7", "8", "9", "10"])
        XCTAssertEqual(pills.filter(\.active).map(\.id), [7])
        XCTAssertEqual(pills.filter(\.occupied).map(\.id), [7])
        XCTAssertEqual(pills.first { $0.id == 7 }?.windowCount, 1)
        XCTAssertEqual(pills.first { $0.id == 6 }?.windowCount, 0)
    }

    func testPillsOccupiedReflectsWindowsAndFirstGroup() {
        let h = Harness()
        h.system.existing("a")
        h.system.existing("b")
        h.start()
        h.wm.state.recordFocus(h.wm.managedWindowIDs[0])
        h.wm.perform(Action(.workspaceMoveSilent, index: 3))
        h.settle()
        let pills = ShellBridge.pills(state: h.wm.state, display: "air", shown: 5)
        XCTAssertEqual(pills.map(\.id), Array(1...5))
        XCTAssertEqual(pills.filter(\.active).map(\.id), [1])
        XCTAssertEqual(pills.filter(\.occupied).map(\.id), [1, 3])
        XCTAssertEqual(pills.reduce(0) { $0 + $1.windowCount }, 2)
    }

    func testPillsBoundaryAndDegenerateShownCount() {
        let h = Harness()
        h.start()
        h.wm.state.focusWorkspace(.numbered(5))
        XCTAssertEqual(ShellBridge.pills(state: h.wm.state, display: "air", shown: 5).map(\.id), Array(1...5))
        h.wm.state.focusWorkspace(.numbered(6))
        XCTAssertEqual(ShellBridge.pills(state: h.wm.state, display: "air", shown: 5).map(\.id), Array(6...10))
        XCTAssertEqual(ShellBridge.pills(state: h.wm.state, display: "air", shown: 0).map(\.id), [6], "shown is clamped to 1")
        XCTAssertEqual(ShellBridge.pills(state: h.wm.state, display: "nope", shown: 3).map(\.id), [1, 2, 3], "unknown display falls back to 1")
    }

    // MARK: shellResponder

    func testShellResponderIsConsultedFirst() {
        let h = Harness()
        h.start()
        var seen: [IPCCommand] = []
        h.wm.shellResponder = { request, command in
            seen.append(command)
            return .success(for: request, result: .string("canned"))
        }
        let r = h.wm.respond(to: IPCRequest(.shellLauncher))
        XCTAssertEqual(r.response.result, .string("canned"))
        XCTAssertTrue(r.response.ok)
        XCTAssertFalse(r.quitRequested)
        XCTAssertEqual(seen, [.shellLauncher])
        // Consulted before everything, even a core WM command.
        let hello = h.wm.respond(to: IPCRequest(.hello))
        XCTAssertEqual(hello.response.result, .string("canned"))
        XCTAssertEqual(seen, [.shellLauncher, .hello])
    }

    func testNilFromTheResponderFallsThroughToTheOldBehavior() {
        let h = Harness()
        h.start()
        let baseline = h.wm.respond(to: IPCRequest(.hello)).response
        var asked = 0
        h.wm.shellResponder = { _, _ in asked += 1; return nil }
        let after = h.wm.respond(to: IPCRequest(.hello)).response
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(after.ok, baseline.ok)
        XCTAssertEqual(after.result, baseline.result)
        XCTAssertEqual(after.result, IPCHello().jsonValue)
        // A shell command nobody answers behaves as before the hook was set.
        let plain = Harness()
        plain.start()
        let before = plain.wm.respond(to: IPCRequest(.shellLauncher)).response
        let withNil = h.wm.respond(to: IPCRequest(.shellLauncher)).response
        XCTAssertEqual(withNil.ok, before.ok)
        XCTAssertEqual(withNil.error, before.error)
    }

    func testUnknownCommandNeverReachesTheResponder() {
        let h = Harness()
        var asked = 0
        h.wm.shellResponder = { _, _ in asked += 1; return nil }
        let r = h.wm.respond(to: IPCRequest(command: "does.not.exist"))
        XCTAssertFalse(r.response.ok)
        XCTAssertEqual(asked, 0)
    }

    // MARK: onLayoutApplied

    func testOnLayoutAppliedFiresOncePerAppliedLayoutPass() {
        let h = Harness()
        h.system.existing("a")
        var fired = 0
        h.wm.onLayoutApplied = { fired += 1 }
        let passes = h.start()
        XCTAssertGreaterThan(passes, 0)
        XCTAssertEqual(fired, passes)

        fired = 0
        h.wm.setNeedsLayout()
        let one = h.settle()
        XCTAssertEqual(fired, one)
        XCTAssertGreaterThan(one, 0)

        fired = 0
        XCTAssertEqual(h.settle(), 0)
        XCTAssertEqual(fired, 0, "no pass, no callback")

        fired = 0
        h.wm.setBarRevealed(true, display: "air")
        let reveal = h.settle()
        XCTAssertEqual(fired, reveal)
    }
}
