import CaelestiaCore
import CaelestiaLayout
import CoreGraphics
import XCTest
@testable import CaelestiaWMKit

/// A WM restart (`wm quit` + relaunch, or a crash) keeps every window on its workspace and side.
@MainActor
final class SessionRestoreTests: XCTestCase {
    private var storeURL: URL!

    override func setUp() {
        storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("session-\(UUID().uuidString).json")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: storeURL) }

    private func harness(_ system: FakeWindowSystem = FakeWindowSystem(), displays: [DisplayInfo] = [TestDisplays.air]) -> Harness {
        let h = Harness(displays: displays, system: system)
        h.wm.sessionStore = SessionSnapshotStore(url: storeURL)
        return h
    }

    /// Quits the WM like `wm quit` (every window comes back on-screen) and starts a new one over
    /// the same windows.
    private func restart(_ h: Harness, displays: [DisplayInfo] = [TestDisplays.air]) -> Harness {
        h.wm.shutdown()
        h.system.flush()
        h.system.stop()
        let next = harness(h.system, displays: displays)
        next.start()
        return next
    }

    func testWindowsKeepTheirWorkspaceAndSideAcrossARestart() {
        let h = harness()
        let a = h.system.existing("a"), b = h.system.existing("b"), c = h.system.existing("c")
        h.start()
        // Not the discovery order: b left, a right; c alone on ws 3.
        h.wm.state.updateTree(of: a.windowID) { _ = $0.swap(a.windowID, b.windowID) }
        h.wm.setNeedsLayout()
        h.settle()
        h.wm.state.recordFocus(c.windowID)
        h.wm.perform(Action(.workspaceMoveSilent, index: 3))
        h.settle()
        let frameA = a.frame, frameB = b.frame
        XCTAssertLessThan(frameB.minX, frameA.minX)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path), "saved on change")

        let n = restart(h)
        XCTAssertEqual(n.wm.counters.restoredFromSession, 3)
        XCTAssertEqual(n.wm.state.workspace(of: a.windowID), .numbered(1))
        XCTAssertEqual(n.wm.state.workspace(of: b.windowID), .numbered(1))
        XCTAssertEqual(n.wm.state.workspace(of: c.windowID), .numbered(3), "not pulled onto ws 1")
        XCTAssertEqual(a.frame, frameA, "same side, same size")
        XCTAssertEqual(b.frame, frameB)
        XCTAssertTrue(n.wm.isParked(c.windowID), "ws 3 is hidden again")
    }

    func testTheVisibleWorkspaceAndSpecialsSurvive() {
        let h = harness()
        let a = h.system.existing("a"), b = h.system.existing("b")
        h.start()
        h.wm.state.recordFocus(b.windowID)
        h.wm.perform(Action(.workspaceMoveSilent, index: 2))
        h.wm.perform(Action(.workspaceFocus, index: 2))
        h.settle()
        h.system.focusedWindowID = a.windowID  // the app focus at restart is on a hidden workspace
        let n = restart(h)
        XCTAssertEqual(n.wm.state.activeNumberedWorkspace(forDisplay: "air"), 2, "ws 2 still shown")
        XCTAssertEqual(n.wm.state.workspace(of: a.windowID), .numbered(1))
        XCTAssertTrue(n.wm.isParked(a.windowID))
        XCTAssertFalse(n.wm.isParked(b.windowID))
    }

    func testAWindowOpenedWhileTheWMWasDownJoinsTheVisibleWorkspace() {
        let h = harness()
        let a = h.system.existing("a"), b = h.system.existing("b")
        h.start()
        h.wm.state.recordFocus(b.windowID)
        h.wm.perform(Action(.workspaceMoveSilent, index: 2))
        h.settle()
        h.wm.shutdown()
        h.system.flush()
        h.system.stop()
        let late = h.system.existing("late", pid: 600)
        let n = harness(h.system)
        n.start()
        XCTAssertEqual(n.wm.state.workspace(of: a.windowID), .numbered(1))
        XCTAssertEqual(n.wm.state.workspace(of: b.windowID), .numbered(2))
        XCTAssertEqual(n.wm.state.workspace(of: late.windowID), .numbered(1))
    }

    func testAnotherAppReusingAWindowIDGetsNoOldPlace() throws {
        let h = harness()
        let a = h.system.existing("a"), b = h.system.existing("b")
        h.start()
        h.wm.state.recordFocus(b.windowID)
        h.wm.perform(Action(.workspaceMoveSilent, index: 4))
        h.settle()
        h.wm.shutdown()
        // b's id now belongs to a different process: the snapshot must not apply to it.
        var snap = try XCTUnwrap(SessionSnapshotStore(url: storeURL).load())
        snap.windows = snap.windows.map { $0.windowID == b.windowID ? .init(windowID: $0.windowID, pid: 999, bundleID: $0.bundleID) : $0 }
        try SessionSnapshotStore(url: storeURL).save(snap)
        h.system.stop()
        let n = harness(h.system)
        n.start()
        XCTAssertEqual(n.wm.state.workspace(of: b.windowID), .numbered(1))
        XCTAssertEqual(n.wm.state.workspace(of: a.windowID), .numbered(1))
    }

    func testASnapshotFromAnEarlierBootIsIgnored() throws {
        let h = harness()
        _ = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        h.wm.state.recordFocus(b.windowID)
        h.wm.perform(Action(.workspaceMoveSilent, index: 4))
        h.settle()
        h.wm.shutdown()
        var snap = try XCTUnwrap(SessionSnapshotStore(url: storeURL).load())
        snap.bootTime -= 3600
        try SessionSnapshotStore(url: storeURL).save(snap)
        h.system.stop()
        let n = harness(h.system)
        n.start()
        XCTAssertEqual(n.wm.counters.restoredFromSession, 0)
        XCTAssertEqual(n.wm.state.workspace(of: b.windowID), .numbered(1))
    }

    func testAMissingDisplayHandsItsWorkspacesOver() {
        let h = harness(displays: [TestDisplays.air, TestDisplays.external])
        let a = h.system.existing("a")
        let e = h.system.existing("e", frame: CGRect(x: 1600, y: 100, width: 600, height: 400))
        h.start()
        XCTAssertEqual(h.wm.state.display(of: e.windowID), "ext")
        let n = restart(h, displays: [TestDisplays.air])
        XCTAssertEqual(n.wm.state.display(of: a.windowID), "air")
        XCTAssertEqual(n.wm.state.display(of: e.windowID), "air")
        XCTAssertNotNil(n.wm.state.workspace(of: e.windowID))
    }

    func testWithoutAStoreNothingIsSavedOrRestored() {
        let h = Harness()
        _ = h.system.existing("a")
        h.start()
        h.wm.shutdown()
        XCTAssertNil(h.wm.sessionStore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }
}
