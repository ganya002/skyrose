import CaelestiaCore
import CaelestiaLayout
import CaelestiaOverlay
import CaelestiaPlatform
import XCTest
@testable import CaelestiaWMKit

/// When the WM asks the window animator for snapshots (and when it must not): only a real
/// change of a visible window's frame animates; re-applied frames, focus changes and a window
/// that merely comes back (hidden app, unminimize) do not.
@MainActor
final class SnapshotAnimationRulesTests: XCTestCase {
    private func harness(_ titles: String...) -> (Harness, FakeWindowAnimator, [FakeWindow]) {
        let h = Harness()
        let anim = FakeWindowAnimator()
        anim.system = h.system
        h.wm.windowAnimator = anim
        let windows = titles.map { h.system.existing($0) }
        return (h, anim, windows)
    }

    func testWindowsDiscoveredAtStartNeverAnimate() {
        let (h, anim, _) = harness("a", "b", "c")
        h.start()
        XCTAssertTrue(anim.requests.isEmpty)
        XCTAssertEqual(h.wm.visiblePlacements.count, 3)
    }

    func testBrandNewWindowStillOpensWithAnAnimation() throws {
        let (h, anim, _) = harness("a")
        h.start()
        let b = h.system.open("b")
        h.settle()
        let open = try XCTUnwrap(anim.lastChanges.first { $0.id == b.windowID })
        XCTAssertEqual(open.kind, .open)
        XCTAssertNil(open.from)
    }

    func testSnapBackOfAnAppMovedWindowIsNotAnimated() {
        let (h, anim, ws) = harness("a", "b")
        h.start()
        let a = ws[0]
        let placed = a.frame
        let writes = a.setFrameCount
        let before = anim.requests.count

        a.appMoves(to: CGRect(x: 700, y: 300, width: 400, height: 300))
        h.settle()
        XCTAssertEqual(a.frame, placed, "the WM restored the frame")
        XCTAssertGreaterThan(a.setFrameCount, writes, "…by writing it again")
        XCTAssertEqual(anim.requests.count, before, "an unchanged target is a re-apply, not an animation")
    }

    func testRepeatedSnapBacksNeverAnimate() {
        let (h, anim, ws) = harness("a")
        h.start()
        let placed = ws[0].frame
        for i in 0..<WindowManager.maxSnapBackRetries {
            ws[0].appMoves(to: CGRect(x: 50 + 30 * Double(i), y: 80, width: 300, height: 200))
            h.settle()
            XCTAssertEqual(ws[0].frame, placed)
        }
        XCTAssertTrue(anim.requests.isEmpty)
    }

    func testFocusChangeProducesNoAnimationRequest() {
        let (h, anim, ws) = harness("a", "b")
        h.start()
        let before = anim.requests.count
        h.wm.state.recordFocus(ws[1].windowID)
        h.wm.setNeedsLayout()
        h.settle()
        h.wm.state.recordFocus(ws[0].windowID)
        h.wm.setNeedsLayout()
        h.settle()
        XCTAssertEqual(anim.requests.count, before)
    }

    func testRealMoveStillAnimatesAsAMove() throws {
        let (h, anim, ws) = harness("a", "b")
        h.start()
        let b = ws[1]
        let c = h.system.open("c")
        h.settle()
        XCTAssertEqual(anim.lastChanges.first { $0.id == c.windowID }?.kind, .open)
        let moves = anim.lastChanges.filter { $0.kind == .move }
        XCTAssertFalse(moves.isEmpty, "the tiles that make room move")
        for m in moves { XCTAssertNotEqual(m.from, m.to, "only real changes are requested") }
        XCTAssertTrue([ws[0].windowID, b.windowID].contains { id in moves.contains { $0.id == id } })
    }

    func testUnmanagedAndManagedAgainWithTheSameIDIsInstantAndCancels() {
        let (h, anim, ws) = harness("a", "b")
        h.start()
        let b = ws[1]
        let id = b.windowID
        h.system.queue(.destroyed(id))  // the window disappears from the AX tree (app hidden)
        h.settle()
        anim.requests.removeAll()
        let cancels = anim.cancelCount

        h.system.queue(.created(b))  // …and is back with the same id (app unhidden)
        h.settle()
        XCTAssertNotNil(h.wm.visiblePlacements[id])
        XCTAssertTrue(anim.requests.isEmpty, "a returning window does not animate")
        XCTAssertGreaterThan(anim.cancelCount, cancels, "any running animation is cancelled")
        XCTAssertEqual(b.frame, h.wm.visiblePlacements[id]?.frame)
    }

    func testAnotherWindowOpeningAfterAReturnAnimatesAgain() throws {
        let (h, anim, ws) = harness("a")
        h.start()
        h.system.queue(.destroyed(ws[0].windowID))
        h.settle()
        anim.requests.removeAll()
        h.system.queue(.created(ws[0]))
        h.settle()
        XCTAssertTrue(anim.requests.isEmpty)
        let n = h.system.open("n")
        h.settle()
        XCTAssertEqual(anim.lastChanges.first { $0.id == n.windowID }?.kind, .open, "the instant pass was a one-off")
    }

    func testHiddenAppComingBackIsInstant() {
        let (h, anim, ws) = harness("a", "b")
        h.start()
        let id = ws[1].windowID
        h.system.queue(.appHidden(ws[1].pid))
        h.settle()
        anim.requests.removeAll()
        let cancels = anim.cancelCount
        h.system.queue(.appShown(ws[1].pid))
        h.settle()
        XCTAssertNotNil(h.wm.visiblePlacements[id])
        XCTAssertTrue(anim.requests.isEmpty, "unhiding an app must not put stills up: \(anim.requests.map(\.changes))")
        XCTAssertGreaterThan(anim.cancelCount, cancels)
    }

    func testUnminimizeIsInstant() {
        let (h, anim, ws) = harness("a", "b")
        h.start()
        let id = ws[1].windowID
        ws[1].isMinimized = true
        h.system.queue(.minimized(id))
        h.settle()
        anim.requests.removeAll()
        let cancels = anim.cancelCount
        ws[1].isMinimized = false
        h.system.queue(.deminiaturized(id))
        h.settle()
        XCTAssertNotNil(h.wm.visiblePlacements[id])
        XCTAssertTrue(anim.requests.isEmpty, "unminimizing must not put stills up: \(anim.requests.map(\.changes))")
        XCTAssertGreaterThan(anim.cancelCount, cancels)
    }
}
