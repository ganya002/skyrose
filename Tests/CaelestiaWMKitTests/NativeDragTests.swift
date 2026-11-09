import CaelestiaCore
import CaelestiaLayout
import CoreGraphics
import XCTest

@testable import CaelestiaWMKit

/// Title-bar drags and edge resizes done with the mouse (left button down while the app moves its
/// own window), versus an app moving a window by itself (button up).
@MainActor
final class NativeDragTests: XCTestCase {
    @MainActor private struct Scene {
        let h: Harness
        let a: FakeWindow
        let b: FakeWindow
        var slotA: CGRect { h.wm.visiblePlacements[a.windowID]!.frame }
        var slotB: CGRect { h.wm.visiblePlacements[b.windowID]!.frame }
    }

    private func scene() -> Scene {
        let h = Harness()
        let a = h.system.existing("a")
        let b = h.system.existing("b")
        h.start()
        return Scene(h: h, a: a, b: b)
    }

    private func titleBar(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.minY + 10) }

    private func assertFrame(_ f: CGRect, _ e: CGRect, _ msg: String = "", line: UInt = #line) {
        XCTAssertEqual(f.minX, e.minX, accuracy: 2, msg, line: line)
        XCTAssertEqual(f.minY, e.minY, accuracy: 2, msg, line: line)
        XCTAssertEqual(f.width, e.width, accuracy: 2, msg, line: line)
        XCTAssertEqual(f.height, e.height, accuracy: 2, msg, line: line)
    }

    /// Presses on `w`, drags it through `frames` (each reported as the app's own move) and returns.
    private func drag(_ s: Scene, _ w: FakeWindow, from press: CGPoint, through frames: [CGRect]) {
        s.h.wm.pointerPressed(at: press)
        s.h.system.isLeftMouseDown = true
        for f in frames {
            w.appMoves(to: f)
            s.h.settle()
        }
    }

    private func release(_ s: Scene, at point: CGPoint) {
        s.h.system.isLeftMouseDown = false
        s.h.wm.pointerReleased(at: point)
        s.h.settle()
    }

    // MARK: drag to nowhere

    func testTitleBarDragReturnsToTheSlotOnRelease() {
        let s = scene()
        let slot = s.slotA, other = s.slotB
        let writesA = s.a.setFrameCount
        let moved = slot.offsetBy(dx: 40, dy: 300)
        drag(s, s.a, from: titleBar(slot), through: [slot.offsetBy(dx: 10, dy: 100), moved])
        XCTAssertEqual(s.a.setFrameCount, writesA, "the WM never writes to a window while the button is down")
        XCTAssertEqual(s.a.frame, moved)
        XCTAssertEqual(s.h.wm.counters.snapBacks, 0, "a user drag is not an app fighting its slot")
        XCTAssertEqual(s.h.wm.counters.autoFloats, 0)

        release(s, at: CGPoint(x: moved.midX, y: slot.maxY + 200))  // dropped on nothing
        assertFrame(s.a.frame, slot)
        assertFrame(s.b.frame, other)
        XCTAssertEqual(s.h.wm.counters.nativeDrops, 1)
        XCTAssertEqual(s.h.wm.counters.nativeResizes, 0)
        XCTAssertFalse(s.h.wm.isFloating(s.a.windowID))
        XCTAssertGreaterThan(s.a.setFrameCount, writesA, "written after the release")
    }

    func testTitleBarDragOntoANeighbourSwapsThem() {
        let s = scene()
        let slotA = s.slotA, slotB = s.slotB
        let dropPoint = CGPoint(x: slotB.midX, y: slotB.midY)
        drag(s, s.a, from: titleBar(slotA), through: [slotA.offsetBy(dx: 300, dy: 50), slotB.offsetBy(dx: 20, dy: 20)])
        release(s, at: dropPoint)
        assertFrame(s.a.frame, slotB, "a took b's slot")
        assertFrame(s.b.frame, slotA, "b took a's slot")
        XCTAssertEqual(s.h.wm.counters.nativeDrops, 1)
        XCTAssertFalse(s.h.wm.isFloating(s.a.windowID))
        XCTAssertFalse(s.h.wm.isFloating(s.b.windowID))
    }

    func testNoWritesToEitherWindowOfASwapUntilRelease() {
        let s = scene()
        let slotA = s.slotA
        let writes = s.a.setFrameCount + s.b.setFrameCount
        drag(s, s.a, from: titleBar(slotA), through: [slotA.offsetBy(dx: 300, dy: 50)])
        s.h.wm.setNeedsLayout()
        s.h.settle()
        XCTAssertEqual(s.a.setFrameCount + s.b.setFrameCount, writes)
    }

    func testPressOnAnotherWindowIsNotADragOfThisOne() {
        let s = scene()
        let slotA = s.slotA, slotB = s.slotB
        // The press landed on b, then a moved itself: that is the app, not the user dragging a.
        s.h.wm.pointerPressed(at: CGPoint(x: slotB.midX, y: slotB.midY))
        s.h.system.isLeftMouseDown = true
        s.a.appMoves(to: slotA.offsetBy(dx: 5, dy: 120))
        s.h.settle()
        XCTAssertEqual(s.h.wm.counters.snapBacks, 1)
        assertFrame(s.a.frame, slotA)
    }

    // MARK: native resize

    func testNativeEdgeResizeChangesTheSplitInsteadOfSnappingBack() {
        let s = scene()
        let slotA = s.slotA, slotB = s.slotB
        var wider = slotA
        wider.size.width += 120
        let press = CGPoint(x: slotA.maxX + 2, y: slotA.midY)  // on the resize handle
        drag(s, s.a, from: press, through: [wider])
        XCTAssertEqual(s.a.frame.width, s.slotA.width, accuracy: 3, "the real window is on the tile, not a stretched proxy")
        release(s, at: press)
        XCTAssertEqual(s.h.wm.counters.nativeResizes, 1)
        XCTAssertEqual(s.h.wm.counters.nativeDrops, 0)
        XCTAssertEqual(s.h.wm.counters.autoFloats, 0)
        XCTAssertFalse(s.h.wm.isFloating(s.a.windowID))
        XCTAssertEqual(s.slotA.width, slotA.width + 120, accuracy: 8)
        XCTAssertEqual(s.a.frame.width, s.slotA.width, accuracy: 2)
        XCTAssertEqual(s.slotB.width, slotB.width - 120, accuracy: 8, "the neighbour gave up the room")
        XCTAssertFalse(s.slotA.intersects(s.slotB))
        assertFrame(s.b.frame, s.slotB)

        // And it is stable: another pass writes nothing.
        let writes = s.a.setFrameCount + s.b.setFrameCount
        s.h.wm.setNeedsLayout()
        s.h.settle()
        XCTAssertEqual(s.a.setFrameCount + s.b.setFrameCount, writes)
    }

    func testNativeResizeMovesTheDraggedWindowAndItsNeighbourLive() {
        let s = scene()
        let slotA = s.slotA, slotB = s.slotB
        var wider = slotA
        wider.size.width += 100
        let writesA = s.a.setFrameCount
        drag(s, s.a, from: CGPoint(x: slotA.maxX + 2, y: slotA.midY), through: [wider])
        XCTAssertGreaterThan(s.a.setFrameCount, writesA, "the window under the cursor is written to its tile")
        XCTAssertEqual(s.a.frame.width, s.slotA.width, accuracy: 3)
        XCTAssertLessThan(s.slotB.width, slotB.width, "b follows the edge while the button is still down")
        release(s, at: CGPoint(x: slotA.maxX + 2, y: slotA.midY))
    }

    // MARK: floating

    func testFloatingWindowDraggedStaysWhereDropped() {
        let h = Harness()
        h.system.existing("tiled")
        let dialog = h.system.existing("dialog")
        dialog.subrole = "AXDialog"
        h.start()
        XCTAssertTrue(h.wm.isFloating(dialog.windowID))
        let writes = dialog.setFrameCount
        let dropped = CGRect(x: 321, y: 222, width: dialog.frame.width, height: dialog.frame.height)
        h.wm.pointerPressed(at: CGPoint(x: dialog.frame.midX, y: dialog.frame.minY + 10))
        h.system.isLeftMouseDown = true
        dialog.appMoves(to: dropped)
        h.settle()
        h.system.isLeftMouseDown = false
        h.wm.pointerReleased(at: CGPoint(x: dropped.midX, y: dropped.minY + 10))
        h.settle()
        XCTAssertEqual(dialog.frame, dropped)
        XCTAssertEqual(dialog.setFrameCount, writes)
        XCTAssertTrue(h.wm.isFloating(dialog.windowID))
        XCTAssertEqual(h.wm.counters.nativeDrops, 0)
        XCTAssertEqual(h.wm.counters.snapBacks, 0)
    }

    // MARK: after the release

    func testLateEchoWithinTheGraceWindowIsReappliedWithoutCounting() {
        let s = scene()
        let slot = s.slotA
        drag(s, s.a, from: titleBar(slot), through: [slot.offsetBy(dx: 30, dy: 200)])
        release(s, at: CGPoint(x: slot.midX, y: slot.maxY + 300))
        assertFrame(s.a.frame, slot)

        // A late notification from the drag arrives after the release.
        s.a.appMoves(to: slot.offsetBy(dx: 31, dy: 201))
        s.h.settle()
        assertFrame(s.a.frame, slot)
        XCTAssertEqual(s.h.wm.counters.snapBacks, 0, "grace re-applies are not snap-backs")
        XCTAssertEqual(s.h.wm.counters.autoFloats, 0)
    }

    func testAppMovesAfterTheGraceWindowCountAsSnapBacks() {
        let s = scene()
        let slot = s.slotA
        drag(s, s.a, from: titleBar(slot), through: [slot.offsetBy(dx: 30, dy: 200)])
        release(s, at: CGPoint(x: slot.midX, y: slot.maxY + 300))
        s.h.clock.now.addTimeInterval(WindowManager.nativeDragGrace + 0.1)
        s.a.appMoves(to: slot.offsetBy(dx: 60, dy: 90))
        s.h.settle()
        XCTAssertEqual(s.h.wm.counters.snapBacks, 1)
        assertFrame(s.a.frame, slot)
    }

    // MARK: app-initiated moves (button up)

    func testAppInitiatedMovesSnapBackAndStayTiled() {
        let s = scene()
        let slot = s.slotA
        XCTAssertFalse(s.h.system.isLeftMouseDown)
        for i in 1...WindowManager.maxSnapBackRetries {
            s.a.appMoves(to: slot.offsetBy(dx: 40, dy: 40 + CGFloat(i)))
            s.h.settle()
            XCTAssertEqual(s.h.wm.counters.snapBacks, i)
            assertFrame(s.a.frame, slot, "snapped back #\(i)")
            XCTAssertFalse(s.h.wm.isFloating(s.a.windowID))
        }
        let neighbour = s.slotB.width
        let wandered = slot.offsetBy(dx: 40, dy: 99)
        s.a.appMoves(to: wandered)
        s.h.settle()
        XCTAssertEqual(s.h.wm.counters.snapBacks, WindowManager.maxSnapBackRetries)
        XCTAssertEqual(s.h.wm.counters.autoFloats, 0)
        XCTAssertFalse(s.h.wm.isFloating(s.a.windowID))
        assertFrame(s.a.frame, wandered, "the burst stops")
        XCTAssertEqual(s.slotB.width, neighbour, accuracy: 1, "b keeps its tile; a was not floated out of the tree")

        s.h.clock.now.addTimeInterval(WindowManager.reconcileInterval + 0.1)
        s.h.wm.reconcileTiling()
        s.h.settle()
        assertFrame(s.a.frame, slot, "reconcile puts it back")
        XCTAssertFalse(s.h.wm.isFloating(s.a.windowID))
    }
}
