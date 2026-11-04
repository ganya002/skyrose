import XCTest
import CaelestiaCore
import CoreGraphics

@testable import CaelestiaOverlay

/// The pure motion model behind the snapshot animator, driven with explicit times.
final class WindowMotionTests: XCTestCase {
    let displayID: CGDirectDisplayID = 1
    let displays: [CGDirectDisplayID: CGRect] = [1: CGRect(x: 0, y: 0, width: 1000, height: 800)]
    let a = CGRect(x: 0, y: 0, width: 400, height: 300)
    let b = CGRect(x: 500, y: 100, width: 300, height: 400)
    let c = CGRect(x: 100, y: 400, width: 200, height: 200)

    func win(_ id: CGWindowID, _ frame: CGRect) -> AnimatedWindow {
        AnimatedWindow(id: id, frame: frame, displayID: displayID, isActive: false)
    }

    func request(_ changes: [WindowFrameChange], _ windows: [AnimatedWindow]) -> WindowAnimationRequest {
        WindowAnimationRequest(changes: changes, windows: windows, displays: displays)
    }

    func sample(_ m: WindowMotionModel, _ id: CGWindowID, at t: TimeInterval) -> WindowMotionSample? {
        m.samples(at: t).first { $0.id == id }
    }

    func assertClose(_ x: CGRect, _ y: CGRect, accuracy: Double = 0.01, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(x.minX, y.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(x.minY, y.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(x.width, y.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(x.height, y.height, accuracy: accuracy, file: file, line: line)
    }

    /// A model with window 1 settled at `a`.
    func settledModel(table: AnimationTable = .gabbySpringy) -> WindowMotionModel {
        var m = WindowMotionModel(table: table)
        m.apply(request([], [win(1, a)]), at: 0)
        return m
    }

    // MARK: move

    func testMoveInterpolatesFromToAndSettles() {
        var m = settledModel()
        XCTAssertTrue(m.isSettled(at: 0))
        m.apply(request([WindowFrameChange(id: 1, kind: .move, from: a, to: b)], [win(1, b)]), at: 10)
        assertClose(sample(m, 1, at: 10)!.frame, a)
        XCTAssertFalse(m.isSettled(at: 10.05))
        let mid = sample(m, 1, at: 10.1)!.frame
        XCTAssertNotEqual(mid.minX, a.minX)
        XCTAssertNotEqual(mid.minX, b.minX)
        XCTAssertTrue(m.isSettled(at: 15))
        assertClose(sample(m, 1, at: 15)!.frame, b)
        XCTAssertEqual(m.items[1]?.target, b)
    }

    func testNewWindowWithMoveChangeStartsFromFrom() {
        var m = WindowMotionModel()
        m.apply(request([WindowFrameChange(id: 2, kind: .move, from: a, to: b)], [win(2, b)]), at: 0)
        assertClose(sample(m, 2, at: 0)!.frame, a)
        assertClose(sample(m, 2, at: 10)!.frame, b)
    }

    func testRetargetMidFlightIsContinuous() {
        var m = settledModel()
        m.apply(request([WindowFrameChange(id: 1, kind: .move, from: a, to: b)], [win(1, b)]), at: 0)
        let before = sample(m, 1, at: 0.12)!.frame
        m.apply(request([WindowFrameChange(id: 1, kind: .move, from: before, to: c)], [win(1, c)]), at: 0.12)
        let after = sample(m, 1, at: 0.12)!.frame
        assertClose(before, after, accuracy: 0.5)
        XCTAssertFalse(m.isSettled(at: 0.13))
        assertClose(sample(m, 1, at: 10)!.frame, c)
    }

    func testDisabledMoveSnaps() {
        var table = AnimationTable.gabbySpringy
        table[.windowsMove] = .disabled
        var m = settledModel(table: table)
        m.apply(request([WindowFrameChange(id: 1, kind: .move, from: a, to: b)], [win(1, b)]), at: 0)
        assertClose(sample(m, 1, at: 0)!.frame, b)
        XCTAssertTrue(m.isSettled(at: 0))
    }

    // MARK: open

    func testOpenPopsIn() {
        var m = WindowMotionModel()
        m.apply(request([WindowFrameChange(id: 1, kind: .open, from: nil, to: a)], [win(1, a)]), at: 0)
        let s0 = sample(m, 1, at: 0)!
        XCTAssertEqual(s0.alpha, 0, accuracy: 0.05)
        XCTAssertEqual(s0.scale, 0.8, accuracy: 0.01)
        XCTAssertLessThan(s0.scale, 1)
        XCTAssertFalse(m.isSettled(at: 0.01))
        let end = sample(m, 1, at: 10)!
        XCTAssertEqual(end.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(end.scale, 1, accuracy: 0.001)
        XCTAssertTrue(m.isSettled(at: 10))
        assertClose(end.frame, a)
    }

    func testOpenWithDisabledPopInAppearsAtOnce() {
        var table = AnimationTable.gabbySpringy
        table[.windowsIn] = .disabled
        var m = WindowMotionModel(table: table)
        m.apply(request([WindowFrameChange(id: 1, kind: .open, from: nil, to: a)], [win(1, a)]), at: 0)
        let s = sample(m, 1, at: 0)!
        XCTAssertEqual(s.alpha, 1)
        XCTAssertEqual(s.scale, 1)
    }

    // MARK: close / leave

    func testCloseOfUnknownWindowCreatesNothing() {
        var m = WindowMotionModel()
        m.apply(request([WindowFrameChange(id: 9, kind: .close, from: a, to: nil)], []), at: 0)
        XCTAssertFalse(m.contains(9))
        XCTAssertTrue(m.isEmpty)
        XCTAssertTrue(m.samples(at: 0).isEmpty)
    }

    func testLeaveOfUnknownWindowFadesAndIsCollected() {
        var m = WindowMotionModel()
        m.apply(request([WindowFrameChange(id: 9, kind: .leave, from: a, to: nil)], []), at: 0)
        XCTAssertTrue(m.contains(9))
        let s0 = sample(m, 9, at: 0)!
        XCTAssertEqual(s0.alpha, 1, accuracy: 0.01)
        assertClose(s0.frame, a)
        let mid = sample(m, 9, at: 0.1)!
        XCTAssertLessThan(mid.alpha, 1)
        XCTAssertTrue(m.collectGone(at: 0.05).isEmpty)
        XCTAssertEqual(m.collectGone(at: 5), [9])
        XCTAssertFalse(m.contains(9))
        XCTAssertTrue(m.samples(at: 5).isEmpty)
    }

    func testLeaveWithoutKnownDisplayIsIgnored() {
        var m = WindowMotionModel()
        let off = CGRect(x: 5000, y: 5000, width: 10, height: 10)
        m.apply(request([WindowFrameChange(id: 9, kind: .leave, from: off, to: nil)], []), at: 0)
        XCTAssertTrue(m.isEmpty)
    }

    func testPrepareCloseThenCloseAnimatesOut() {
        var m = WindowMotionModel()
        let scene = request([], [win(1, a), win(2, b)])
        m.prepareClose(1, request: scene, at: 0)
        XCTAssertTrue(m.contains(1))
        XCTAssertEqual(sample(m, 1, at: 0)!.alpha, 1, accuracy: 0.001)
        m.apply(request([WindowFrameChange(id: 1, kind: .close, from: a, to: nil)], [win(2, b)]), at: 1)
        let mid = sample(m, 1, at: 1.1)!
        XCTAssertLessThan(mid.alpha, 1)
        XCTAssertLessThan(mid.scale, 1)
        XCTAssertNotNil(sample(m, 2, at: 1.1))
        XCTAssertEqual(m.collectGone(at: 6), [1])
        XCTAssertTrue(m.contains(2))
    }

    func testDisabledOutRemovesAtOnce() {
        var table = AnimationTable.gabbySpringy
        table[.windowsOut] = .disabled
        var m = WindowMotionModel(table: table)
        m.prepareClose(1, request: request([], [win(1, a)]), at: 0)
        m.apply(request([WindowFrameChange(id: 1, kind: .close, from: a, to: nil)], []), at: 1)
        XCTAssertFalse(m.contains(1))
    }

    func testVanishedWithoutChangeIsDroppedImmediately() {
        var m = settledModel()
        m.apply(request([], []), at: 1)
        XCTAssertTrue(m.isEmpty)
    }

    // MARK: drag

    func testDragFollowsPointerAndSettlesAfterEnd() {
        var m = settledModel()
        m.beginDrag(1, at: 0)
        XCTAssertTrue(sample(m, 1, at: 0)!.isDragged)
        XCTAssertFalse(m.isSettled(at: 100))
        m.drag(1, to: b)
        assertClose(sample(m, 1, at: 0.5)!.frame, b)
        m.drag(1, to: c)
        assertClose(sample(m, 1, at: 0.5)!.frame, c)
        XCTAssertEqual(sample(m, 1, at: 5)!.scale, WindowMotionModel.dragScale, accuracy: 0.001)
        m.endDrag(1, at: 5)
        XCTAssertFalse(sample(m, 1, at: 5)!.isDragged)
        XCTAssertFalse(m.isSettled(at: 5))
        let end = sample(m, 1, at: 15)!
        assertClose(end.frame, a)
        XCTAssertEqual(end.scale, 1, accuracy: 0.001)
        XCTAssertTrue(m.isSettled(at: 15))
    }

    func testRelayoutDuringDragRetargetsSlot() {
        var m = settledModel()
        m.beginDrag(1, at: 0)
        m.drag(1, to: c)
        m.apply(request([], [win(1, b)]), at: 1)
        assertClose(sample(m, 1, at: 1)!.frame, c)
        m.endDrag(1, at: 1)
        assertClose(sample(m, 1, at: 15)!.frame, b)
    }

    func testDragOfUnknownWindowIsNoOp() {
        var m = WindowMotionModel()
        m.beginDrag(5, at: 0)
        m.drag(5, to: a)
        m.endDrag(5, at: 0)
        XCTAssertTrue(m.isEmpty)
    }

    // MARK: request helpers

    func testDisplayForRectPicksLargestOverlap() {
        let ds: [CGDirectDisplayID: CGRect] = [1: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                               2: CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        XCTAssertEqual(WindowAnimationRequest.display(for: CGRect(x: 900, y: 0, width: 300, height: 100), in: ds), 2)
        XCTAssertEqual(WindowAnimationRequest.display(for: CGRect(x: 800, y: 0, width: 300, height: 100), in: ds), 1)
        XCTAssertNil(WindowAnimationRequest.display(for: CGRect(x: 5000, y: 0, width: 10, height: 10), in: ds))
    }

    func testAffectedDisplays() {
        let ds: [CGDirectDisplayID: CGRect] = [1: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                               2: CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        let r = WindowAnimationRequest(changes: [
            WindowFrameChange(id: 1, kind: .move, from: a, to: b),
            WindowFrameChange(id: 2, kind: .close, from: CGRect(x: 1100, y: 0, width: 100, height: 100), to: nil),
            WindowFrameChange(id: 3, kind: .open, from: nil, to: nil),
        ], windows: [], displays: ds)
        XCTAssertEqual(r.affectedDisplays, [1, 2])
        XCTAssertEqual(WindowAnimationRequest(changes: [], windows: [], displays: ds).affectedDisplays, [])
    }

    @MainActor
    func testInstantAnimatorCommitsSynchronously() {
        let animator = InstantWindowAnimator()
        var commits = 0
        animator.animate(request([], []), commit: { commits += 1 })
        XCTAssertEqual(commits, 1)
        XCTAssertFalse(animator.isCovering(1))
        XCTAssertFalse(animator.prepareClose(1, scene: request([], [])))
        XCTAssertFalse(animator.beginDrag(1, pointer: .zero, scene: request([], [])))
    }
}
