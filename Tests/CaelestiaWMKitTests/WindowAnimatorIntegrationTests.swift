import CaelestiaCore
import CaelestiaLayout
import CaelestiaOverlay
import CaelestiaPlatform
import XCTest
@testable import CaelestiaWMKit

/// A window animator that records what the WM asks and can hold the commit back.
@MainActor
final class FakeWindowAnimator: WindowAnimator {
    var requests: [WindowAnimationRequest] = []
    var pendingCommits: [() -> Void] = []
    /// When false, every commit runs inside `animate` (like the instant animator).
    var defers = false
    var covering: Set<CGWindowID> = []
    var prepareCloseIDs: [CGWindowID] = []
    /// What the system looked like when `prepareClose` was called.
    var windowsAtPrepareClose: [Set<WindowID>] = []
    var prepareCloseResult = true
    var cancelCount = 0
    var visibleReports: [[AnimatedWindow]] = []
    weak var system: FakeWindowSystem?

    var lastChanges: [WindowFrameChange] { requests.last?.changes ?? [] }

    func animate(_ request: WindowAnimationRequest, commit: @escaping () -> Void) {
        requests.append(request)
        if defers { pendingCommits.append(commit) } else { commit() }
    }

    func commitAll() {
        let c = pendingCommits
        pendingCommits = []
        for f in c { f() }
    }

    func isCovering(_ id: CGWindowID) -> Bool { covering.contains(id) }

    func prepareClose(_ id: CGWindowID, scene: WindowAnimationRequest) -> Bool {
        prepareCloseIDs.append(id)
        windowsAtPrepareClose.append(Set(system?.windows.keys.map { $0 } ?? []))
        return prepareCloseResult
    }

    func beginDrag(_ id: CGWindowID, pointer: CGPoint, scene: WindowAnimationRequest) -> Bool { false }
    func updateDrag(pointer: CGPoint, dropTarget: CGRect?) {}
    func endDrag() {}
    func windowsChanged(visible: [AnimatedWindow]) { visibleReports.append(visible) }
    func cancel() { cancelCount += 1 }
    var applied: [(CGWindowID, CGRect)] = []
    func frameApplied(_ id: CGWindowID, actual: CGRect) { applied.append((id, actual)) }
}

@MainActor
final class WindowAnimatorIntegrationTests: XCTestCase {
    private func harness() -> (Harness, FakeWindowAnimator) {
        let h = Harness()
        let a = FakeWindowAnimator()
        a.system = h.system
        h.wm.windowAnimator = a
        return (h, a)
    }

    private func writes(_ ws: FakeWindow...) -> Int { ws.reduce(0) { $0 + $1.setFrameCount + $1.setPositionCount } }

    // (a)
    func testRetileSendsMovesAndWritesOnlyOnCommit() throws {
        let (h, anim) = harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        XCTAssertTrue(anim.requests.isEmpty, "windows discovered at start never animate")
        let beforeA = a.frame, beforeB = b.frame
        let writesBefore = writes(a, b)

        anim.defers = true
        let c = h.system.open("c")
        h.settle()
        let req = try XCTUnwrap(anim.requests.last)
        XCTAssertEqual(anim.pendingCommits.count, 1)
        // Nothing written yet: windows keep their old frames.
        XCTAssertEqual(writes(a, b, c), writesBefore + c.setFrameCount + c.setPositionCount)
        XCTAssertEqual(c.setFrameCount, 0)
        XCTAssertEqual(a.frame, beforeA)
        XCTAssertEqual(b.frame, beforeB)

        XCTAssertNil(req.changes.first { $0.id == a.windowID }, "a's new size is not a scaled still")
        XCTAssertTrue(h.wm.liveResizeSchedule.contains(a.windowID))
        let toA = try XCTUnwrap(h.wm.visiblePlacements[a.windowID]?.frame)
        XCTAssertNotEqual(beforeA, toA)
        XCTAssertEqual(req.windows.map(\.id).sorted(), [a.windowID, b.windowID, c.windowID])

        anim.commitAll()
        // The first sample is the frame the window already has. It reaches the slot on the spring.
        XCTAssertEqual(a.frame, beforeA)
        h.clock.now.addTimeInterval(h.wm.liveResizeSchedule.spec.duration + 0.05)
        h.wm.stepLiveResize()
        XCTAssertEqual(a.frame, toA)
        XCTAssertGreaterThan(c.setFrameCount, 0)
        XCTAssertEqual(c.frame, h.wm.visiblePlacements[c.windowID]?.frame)
    }

    // (b)
    func testNewWindowYieldsOpenChange() throws {
        let (h, anim) = harness()
        h.system.existing("a")
        h.start()
        anim.defers = true
        let b = h.system.open("b")
        h.settle()
        let open = try XCTUnwrap(anim.lastChanges.first { $0.id == b.windowID })
        XCTAssertEqual(open.kind, .open)
        XCTAssertNil(open.from)
        XCTAssertEqual(open.to, h.wm.visiblePlacements[b.windowID]?.frame)
        anim.commitAll()
    }

    // (c)
    func testWindowGoingAwayYieldsClose() throws {
        let (h, anim) = harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        let oldFrame = try XCTUnwrap(h.wm.visiblePlacements[a.windowID]?.frame)
        anim.defers = true
        h.system.destroy(a.windowID)
        h.settle()
        let close = try XCTUnwrap(anim.lastChanges.first { $0.id == a.windowID })
        XCTAssertEqual(close.kind, .close)
        XCTAssertEqual(close.from, oldFrame)
        XCTAssertNil(close.to)
        XCTAssertFalse(anim.lastChanges.contains { $0.id == a.windowID && $0.kind == .leave })
        XCTAssertFalse(try XCTUnwrap(anim.requests.last).windows.contains { $0.id == a.windowID })
        XCTAssertFalse(anim.lastChanges.contains { $0.id == b.windowID && $0.kind == .move }, "b's new size is not a scaled still")
        XCTAssertTrue(h.wm.liveResizeSchedule.contains(b.windowID))
        anim.commitAll()
    }

    // (d)
    func testMovingToHiddenWorkspaceLeavesAndParksOnCommit() throws {
        let (h, anim) = harness()
        let a = h.system.existing("a")
        let c = h.system.existing("c")
        h.start()
        h.wm.state.recordFocus(c.windowID)
        let oldFrame = try XCTUnwrap(h.wm.visiblePlacements[c.windowID]?.frame)
        anim.defers = true
        h.wm.perform(Action(.workspaceMoveSilent, index: 3))
        h.settle()
        let leave = try XCTUnwrap(anim.lastChanges.first { $0.id == c.windowID })
        XCTAssertEqual(leave.kind, .leave)
        XCTAssertEqual(leave.from, oldFrame)
        XCTAssertNil(leave.to)
        XCTAssertFalse(h.wm.isParked(c.windowID), "parking waits for the commit")
        XCTAssertEqual(c.frame, oldFrame)
        XCTAssertFalse(try XCTUnwrap(anim.requests.last).windows.contains { $0.id == c.windowID })

        anim.commitAll()
        XCTAssertTrue(h.wm.isParked(c.windowID))
        XCTAssertNotEqual(c.frame, oldFrame)
        _ = a
    }

    // (e)
    func testCloseActionPreparesTheAnimatorBeforeClosing() throws {
        let (h, anim) = harness()
        let a = h.system.existing("a")
        h.start()
        h.wm.state.recordFocus(a.windowID)
        h.wm.perform(Action(.windowClose))
        XCTAssertEqual(anim.prepareCloseIDs, [a.windowID])
        XCTAssertEqual(anim.windowsAtPrepareClose, [[a.windowID]], "the window still existed when the cover went up")
        XCTAssertNil(h.system.windows[a.windowID], "then it was closed")
    }

    func testCloseActionWithoutAnimatorStillCloses() {
        let h = Harness()
        let a = h.system.existing("a")
        h.start()
        h.wm.state.recordFocus(a.windowID)
        h.wm.perform(Action(.windowClose))
        XCTAssertNil(h.system.windows[a.windowID])
    }

    // (f)
    func testRestoreEverythingCancelsTheAnimator() {
        let (h, anim) = harness()
        h.system.existing("a")
        h.start()
        let before = anim.cancelCount
        h.wm.restoreEverything()
        XCTAssertEqual(anim.cancelCount, before + 1)
    }

    func testPanicCancelsTheAnimator() {
        let (h, anim) = harness()
        h.system.existing("a")
        h.start()
        let before = anim.cancelCount
        h.wm.panic()
        XCTAssertGreaterThan(anim.cancelCount, before)
        XCTAssertEqual(h.quitCount, 1)
    }

    // (g)
    func testNoAnimatorWritesImmediately() {
        let h = Harness()
        let a = h.system.existing("a")
        h.start()
        let b = h.system.open("b")
        h.settle()
        XCTAssertEqual(a.frame, h.wm.visiblePlacements[a.windowID]?.frame)
        XCTAssertEqual(b.frame, h.wm.visiblePlacements[b.windowID]?.frame)
    }

    func testInstantAnimatorMatchesNoAnimator() {
        func run(_ animator: (any WindowAnimator)?) -> [CGRect] {
            let h = Harness()
            h.wm.windowAnimator = animator
            let a = h.system.existing("a")
            h.start()
            let b = h.system.open("b")
            h.settle()
            h.wm.state.recordFocus(b.windowID)
            h.wm.perform(Action(.workspaceMoveSilent, index: 2))
            h.settle()
            return [a.frame, b.frame]
        }
        XCTAssertEqual(run(InstantWindowAnimator()), run(nil))
    }

    func testAnimatorIsToldWhichWindowsAreVisible() throws {
        let (h, anim) = harness()
        let a = h.system.existing("a")
        h.start()
        XCTAssertEqual(anim.visibleReports.last?.map(\.id), [a.windowID])
    }

    func testNoChangesMeansNoAnimateCall() {
        let (h, anim) = harness()
        h.system.existing("a")
        h.start()
        let n = anim.requests.count
        h.wm.setNeedsLayout()
        h.settle()
        XCTAssertEqual(anim.requests.count, n)
    }

    // isCovering -> borders snap
    func testCoveredWindowBordersSnapInstead() throws {
        let (h, anim) = harness()
        let d = TestDecorations()
        h.wm.decorations = d
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        anim.covering = [a.windowID]
        h.wm.setNeedsLayout()
        h.settle()
        let scene = try XCTUnwrap(d.lastScene)
        let ta = try XCTUnwrap(scene.borders.first { $0.id == a.windowID })
        let tb = try XCTUnwrap(scene.borders.first { $0.id == b.windowID })
        XCTAssertEqual(ta.motion, .snap)
        XCTAssertEqual(ta.appear, .instant)
        XCTAssertEqual(tb.motion, .animate)
    }

    func testCoveredWindowThatClosesVanishesInstantly() throws {
        let (h, anim) = harness()
        let d = TestDecorations()
        h.wm.decorations = d
        let a = h.system.existing("a")
        h.system.existing("b")
        h.start()
        anim.covering = [a.windowID]
        h.system.destroy(a.windowID)
        h.settle()
        XCTAssertEqual(d.lastScene?.vanish[a.windowID], .instant)
    }

    func testUncoveredWindowThatClosesFadesOut() throws {
        let (h, _) = harness()
        let d = TestDecorations()
        h.wm.decorations = d
        let a = h.system.existing("a")
        h.system.existing("b")
        h.start()
        h.system.destroy(a.windowID)
        h.settle()
        XCTAssertEqual(d.lastScene?.vanish[a.windowID], .fadeOut)
    }

    /// Live finding (round 4): a window whose app refused its new size was drawn at the slot
    /// size until the cover faded onto the smaller real window. The WM reports the frame the
    /// app really took so the animation ends there; an unchanged read-back is not reported.
    func testAFrameTheAppChoseItselfIsReportedToTheAnimator() {
        let (h, a) = harness()
        let w = h.system.existing("w")
        h.start()
        a.applied.removeAll()
        // The app now clamps its width to 900: the next retile reads back 900, not the slot.
        w.minSize = CGSize(width: 900, height: 0)
        h.system.open("other")
        h.settle()
        XCTAssertFalse(a.applied.contains { $0.0 == w.windowID }, "a resize has no cover to retarget: \(a.applied)")
        XCTAssertTrue(h.wm.liveResizeSchedule.contains(w.windowID))
        // A new window has no previous frame to compare with (an app may apply its size a moment
        // later): its first write is never reported. A window that ignores writes is reported
        // where it really is.
        a.applied.removeAll()
        let frozen = h.system.open("frozen") { $0.ignoresWrites = true }
        h.settle()
        for (id, f) in a.applied where id == frozen.windowID { XCTAssertEqual(f, frozen.frame) }
    }
}
