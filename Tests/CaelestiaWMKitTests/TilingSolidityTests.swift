import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CoreGraphics
import XCTest

@testable import CaelestiaWMKit

/// Part 9i: every normal window stays tiled. Float only for a user choice or a float rule
/// (dialogs, sheets, panels, utility windows). Nothing overlaps. Headless stand-in for a
/// TestWindows stress run: the fake windows clamp like apps that refuse to shrink.
@MainActor
final class TilingSolidityTests: XCTestCase {
    private func assertSolid(_ h: Harness, _ note: String, file: StaticString = #filePath, line: UInt = #line) {
        let visible = h.wm.visiblePlacements.values.filter { $0.kind == .tiled }
        for i in visible.indices {
            for j in visible.indices where j > i {
                XCTAssertFalse(
                    WorkspaceLayout.overlaps(visible[i].frame, visible[j].frame),
                    "\(note): \(visible[i].window) overlaps \(visible[j].window)", file: file, line: line
                )
            }
        }
        for id in h.wm.managedWindowIDs {
            guard let d = h.wm.handle(for: id)?.descriptor() else { continue }
            let allowed = d.isDialogLike || d.isFixedSize || !d.isStandardWindow
            if !allowed {
                XCTAssertFalse(h.wm.isFloating(id), "\(note): #\(id) \(d.title) floated", file: file, line: line)
            }
        }
        XCTAssertEqual(h.wm.counters.autoFloats, 0, note, file: file, line: line)
    }

    func testFiftyWindowsSpawnCloseAndSwitchWorkspacesStayTiled() {
        let h = Harness(displays: [TestDisplays.air, TestDisplays.external])
        h.start()
        var opened: [FakeWindow] = []
        for i in 0..<55 {
            let displayPid = pid_t(i < 30 ? 800 : 900)
            opened.append(h.system.open("w\(i)", pid: displayPid))
            if i == 12 { _ = h.press("2", Harness.lopt) }
            if i == 28 {
                h.screens.change(to: [])
                h.screens.change(to: [TestDisplays.air, TestDisplays.external])
                h.wm.noteSessionEvent("sleep")
            }
            if i % 10 == 9 { h.settle() }
        }
        h.settle()
        assertSolid(h, "after spawn")
        XCTAssertGreaterThanOrEqual(h.wm.managedWindowIDs.count, 55)
        for w in opened.prefix(30) { h.system.destroy(w.windowID) }
        h.settle()
        _ = h.press("1", Harness.lopt)
        h.settle()
        assertSolid(h, "after close and switch")
    }

    func testWideMinimumsFlipTheSplitInsteadOfOverlapping() {
        let h = Harness()
        let a = h.system.existing("a")
        a.minSize = CGSize(width: 900, height: 0)
        h.start()
        let b = h.system.open("b") { $0.minSize = CGSize(width: 900, height: 0) }
        h.settle()
        assertSolid(h, "wide")
        XCTAssertTrue(h.isOnScreen(a) && h.isOnScreen(b), "the other direction fits both")
        XCTAssertGreaterThanOrEqual(a.frame.width, 900)
        XCTAssertGreaterThanOrEqual(b.frame.width, 900)
        XCTAssertFalse(WorkspaceLayout.overlaps(a.frame, b.frame))
        XCTAssertGreaterThanOrEqual(h.wm.counters.splitFlips, 1)
        let state = try? h.wm.respond(to: IPCRequest(.queryState)).response.result?.decode(StateQueryEntry.self)
        XCTAssertTrue(state?.tilingNotes.contains { $0.contains("split direction") } == true)
    }

    func testImpossibleMinimumsStackInsteadOfFloating() throws {
        let h = Harness()
        let a = h.system.existing("a")
        a.minSize = CGSize(width: 2000, height: 2000)
        h.start()
        let b = h.system.open("b") { $0.minSize = CGSize(width: 2000, height: 2000) }
        h.settle()
        assertSolid(h, "huge")
        let onScreen = [a, b].filter { h.isOnScreen($0) }
        XCTAssertEqual(onScreen.count, 1, "one tile is shown; the other is parked")
        let placement = try XCTUnwrap(h.wm.visiblePlacements[onScreen[0].windowID])
        XCTAssertTrue(h.wm.usableArea(of: TestDisplays.air).contains(placement.frame), "the tile is the best fit, inside the screen")
        XCTAssertGreaterThanOrEqual(h.wm.counters.monocleLayouts, 1)
    }

    func testWakePutsADriftedWindowBackAndASecondReconcileIsQuiet() {
        let h = Harness()
        let a = h.system.existing("a")
        h.system.existing("b")
        h.start()
        let slot = a.frame
        a.frame = slot.offsetBy(dx: 80, dy: 40)
        h.wm.noteSessionEvent("wake")
        h.settle()
        XCTAssertEqual(a.frame, slot)
        XCTAssertFalse(h.wm.isFloating(a.windowID))
        let writes = a.setFrameCount
        h.wm.reconcileTiling()
        h.settle()
        XCTAssertEqual(a.setFrameCount, writes)
        assertSolid(h, "wake")
    }

    func testAFloatThatResizedWithoutAnEventGetsItsBorderBackOnReconcile() {
        let h = Harness()
        let w = h.system.existing("floaty")
        h.start()
        h.wm.state.recordFocus(w.windowID)
        XCTAssertTrue(h.wm.perform(Action(.windowToggleFloat)))
        h.settle()
        XCTAssertTrue(h.wm.isFloating(w.windowID))
        // The app shrinks itself with no notification (a window sizing itself as it appears).
        let small = CGRect(x: 100, y: 120, width: 300, height: 200)
        w.frame = small
        h.wm.reconcileTiling()
        h.settle()
        XCTAssertEqual(h.wm.floatingFrame(w.windowID), small)
        XCTAssertEqual(h.wm.borderFrames[w.windowID]?.insetBy(dx: 1, dy: 1), small, "the border is back on the window")
        let writes = w.setFrameCount
        h.wm.reconcileTiling()
        h.settle()
        XCTAssertEqual(w.setFrameCount, writes, "the window is left alone")
    }

    func testAWindowThatAppearsWithoutAnEventIsTiledOnReconcile() {
        let h = Harness()
        h.start()
        let late = FakeWindow(id: 4242, pid: 500, bundleID: "com.example.app", title: "late", frame: CGRect(x: 40, y: 40, width: 500, height: 400))
        late.system = h.system
        h.system.windows[late.windowID] = late
        XCTAssertFalse(h.wm.isManaged(late.windowID))
        h.wm.reconcileTiling()
        h.settle()
        XCTAssertTrue(h.wm.isManaged(late.windowID))
        XCTAssertFalse(h.wm.isFloating(late.windowID))
        assertSolid(h, "stray")
        let writes = late.setFrameCount
        h.wm.reconcileTiling()
        h.settle()
        XCTAssertEqual(late.setFrameCount, writes, "idempotent")
    }

    func testLeavingNativeFullscreenTilesTheWindow() {
        let h = Harness()
        let w = h.system.existing("full")
        w.isNativeFullscreen = true
        h.start()
        XCTAssertFalse(h.wm.isManaged(w.windowID))
        w.isNativeFullscreen = false
        h.wm.noteSessionEvent("fullscreen exit")
        h.settle()
        XCTAssertTrue(h.wm.isManaged(w.windowID))
        XCTAssertFalse(h.wm.isFloating(w.windowID))
        XCTAssertTrue(h.isOnScreen(w))
    }

    func testADialogStillFloatsAndANormalWindowDoesNot() {
        let h = Harness()
        h.start()
        let dialog = h.system.open("Save") { $0.subrole = "AXDialog" }
        let normal = h.system.open("Editor")
        h.settle()
        XCTAssertTrue(h.wm.isFloating(dialog.windowID))
        XCTAssertFalse(h.wm.isFloating(normal.windowID))
        assertSolid(h, "dialog")
    }

    func testUserFloatSurvivesANewWindowAndARestartOfTheLedger() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("user-float-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let h = Harness()
        h.wm.userFloatLedgerURL = url
        let a = h.system.existing("Notes", bundle: "com.example.notes")
        h.start()
        h.wm.state.recordFocus(a.windowID)
        XCTAssertTrue(h.wm.perform(Action(.windowToggleFloat)))
        h.settle()
        XCTAssertTrue(h.wm.isFloating(a.windowID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        h.wm.shutdown()
        let next = Harness()
        next.wm.userFloatLedgerURL = url
        let b = next.system.existing("Notes", bundle: "com.example.notes")
        next.start()
        XCTAssertTrue(next.wm.isFloating(b.windowID), "same app and title stays floating")
        next.wm.state.recordFocus(b.windowID)
        XCTAssertTrue(next.wm.perform(Action(.windowToggleFloat)))
        next.settle()
        XCTAssertFalse(next.wm.isFloating(b.windowID))
        let c = next.system.open("Notes", bundle: "com.example.notes")
        next.settle()
        XCTAssertFalse(next.wm.isFloating(c.windowID), "tiling it back is remembered too")
        let other = next.system.open("Notes", bundle: "com.example.other")
        next.settle()
        XCTAssertFalse(next.wm.isFloating(other.windowID))
    }

    func testDaemonRestartKeepsAUserFloatedWindowFloating() {
        let store = FileManager.default.temporaryDirectory.appendingPathComponent("session-float-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: store) }
        let system = FakeWindowSystem()
        let h = Harness(system: system)
        h.wm.sessionStore = SessionSnapshotStore(url: store)
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        h.wm.state.recordFocus(a.windowID)
        XCTAssertTrue(h.wm.perform(Action(.windowToggleFloat)))
        h.settle()
        h.wm.shutdown()
        system.flush()
        system.stop()
        let next = Harness(system: system)
        next.wm.sessionStore = SessionSnapshotStore(url: store)
        next.start()
        XCTAssertTrue(next.wm.isFloating(a.windowID))
        XCTAssertFalse(next.wm.isFloating(b.windowID))
        let tiled = next.wm.visiblePlacements.values.filter { $0.kind == .tiled }
        for i in tiled.indices {
            for j in tiled.indices where j > i {
                XCTAssertFalse(WorkspaceLayout.overlaps(tiled[i].frame, tiled[j].frame))
            }
        }
    }
}
