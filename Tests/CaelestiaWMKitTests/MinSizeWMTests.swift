import CaelestiaCore
import CaelestiaLayout
import CoreGraphics
import XCTest

@testable import CaelestiaWMKit

/// How the WM learns, shares and gives up on window minimum sizes.
@MainActor
final class MinSizeWMTests: XCTestCase {
    // MARK: learning

    func testMinSizeNeedsASecondConfirmingReadBack() {
        let h = Harness()
        let w = h.system.existing("w")
        h.start()
        let id = w.windowID
        let target = CGRect(x: 100, y: 100, width: 400, height: 300)
        let readBack = CGRect(x: 100, y: 100, width: 520, height: 300)

        XCTAssertTrue(h.wm.learnMinSize(id, target: target, readBack: readBack), "first sighting asks for a re-write")
        XCTAssertNil(h.wm.learnedMinSize(id), "not learned from one read-back")
        XCTAssertEqual(h.wm.counters.minSizesLearned, 0)

        XCTAssertTrue(h.wm.learnMinSize(id, target: target, readBack: readBack), "the second identical read-back confirms")
        XCTAssertEqual(h.wm.learnedMinSize(id)?.width, 520)
        XCTAssertEqual(h.wm.learnedMinSize(id)?.height ?? 0, 0, "an axis that did not grow stays unknown")
        XCTAssertEqual(h.wm.counters.minSizesLearned, 1)

        // Seen again (it would only happen if the layout had not made room): confirming it
        // again teaches nothing new, so it never counts twice.
        _ = h.wm.learnMinSize(id, target: target, readBack: readBack)
        XCTAssertFalse(h.wm.learnMinSize(id, target: target, readBack: readBack), "known already: nothing new to lay out")
        XCTAssertEqual(h.wm.counters.minSizesLearned, 1)
    }

    func testAnUnconfirmedReadBackIsForgottenWhenTheWindowObeys() {
        let h = Harness()
        let w = h.system.existing("w")
        h.start()
        let id = w.windowID
        let target = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertTrue(h.wm.learnMinSize(id, target: target, readBack: CGRect(x: 100, y: 100, width: 520, height: 300)))
        // The app applied the size late: the next read-back is the target.
        XCTAssertFalse(h.wm.learnMinSize(id, target: target, readBack: target))
        // So a later oversize read-back starts over instead of confirming the stale one.
        XCTAssertTrue(h.wm.learnMinSize(id, target: target, readBack: CGRect(x: 100, y: 100, width: 520, height: 300)))
        XCTAssertNil(h.wm.learnedMinSize(id))
    }

    func testDifferentReadBacksDoNotConfirmEachOther() {
        let h = Harness()
        let w = h.system.existing("w")
        h.start()
        let id = w.windowID
        let target = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertTrue(h.wm.learnMinSize(id, target: target, readBack: CGRect(x: 0, y: 0, width: 520, height: 300)))
        XCTAssertTrue(h.wm.learnMinSize(id, target: target, readBack: CGRect(x: 0, y: 0, width: 700, height: 300)))
        XCTAssertNil(h.wm.learnedMinSize(id))
        XCTAssertTrue(h.wm.learnMinSize(id, target: target, readBack: CGRect(x: 0, y: 0, width: 700, height: 300)))
        XCTAssertEqual(h.wm.learnedMinSize(id)?.width, 700)
    }

    func testNullAndSmallerReadBacksLearnNothing() {
        let h = Harness()
        let w = h.system.existing("w")
        h.start()
        let target = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertFalse(h.wm.learnMinSize(w.windowID, target: target, readBack: .null))
        XCTAssertFalse(h.wm.learnMinSize(w.windowID, target: target, readBack: CGRect(x: 0, y: 0, width: 400.5, height: 300)))
        XCTAssertFalse(h.wm.learnMinSize(w.windowID, target: target, readBack: CGRect(x: 0, y: 0, width: 200, height: 100)))
        XCTAssertNil(h.wm.learnedMinSize(w.windowID))
    }

    func testAWindowThatRefusesToShrinkIsLearnedThroughRealWrites() {
        let h = Harness()
        h.system.existing("a")
        h.start()
        let b = h.system.open("b") { $0.minSize = CGSize(width: 900, height: 0) }
        h.settle()
        XCTAssertEqual(h.wm.learnedMinSize(b.windowID)?.width, 900)
        XCTAssertEqual(h.wm.counters.minSizesLearned, 1)
    }

    // MARK: per-app hints

    func testAMinimumLearnedForAnAppAppliesToItsNextWindow() {
        let h = Harness()
        h.system.existing("anchor")
        h.start()
        let first = h.system.open("first", bundle: "com.example.picky") { $0.minSize = CGSize(width: 800, height: 0) }
        h.settle()
        XCTAssertEqual(h.wm.learnedMinSize(first.windowID)?.width, 800)

        // A second window of the same bundle gets the hint before any write.
        let second = h.system.open("second", bundle: "com.example.picky")
        XCTAssertEqual(h.wm.learnedMinSize(second.windowID)?.width, 800, "known from its first layout pass")
        h.settle()
        XCTAssertGreaterThanOrEqual(h.wm.visiblePlacements[second.windowID]!.frame.width, 800)

        // Another app is not affected.
        let other = h.system.open("other", bundle: "com.example.other")
        XCTAssertNil(h.wm.learnedMinSize(other.windowID))
    }

    /// Live finding (round 4): one TestWindows window with an 800 pt minimum made every new
    /// window of the app float, because the app's hint counted as each new window's own minimum.
    /// A hint gives room but never floats; it is dropped when it cannot fit.
    func testAnAppHintNeverFloatsAWindowThatDoesNotNeedIt() {
        let h = Harness()
        h.system.existing("anchor")
        h.start()
        let picky = h.system.open("picky", bundle: "com.example.app2") { $0.minSize = CGSize(width: 800, height: 0) }
        h.settle()
        XCTAssertEqual(h.wm.learnedMinSize(picky.windowID)?.width, 800)
        let before = h.wm.counters.autoFloats
        // Two more windows of the same app: three 800 pt hints cannot fit side by side.
        let x = h.system.open("x", bundle: "com.example.app2")
        let y = h.system.open("y", bundle: "com.example.app2")
        h.settle()
        XCTAssertFalse(h.wm.isFloating(x.windowID), "a hinted window is not floated")
        XCTAssertFalse(h.wm.isFloating(y.windowID), "a hinted window is not floated")
        XCTAssertEqual(h.wm.counters.autoFloats, before)
        let area = h.wm.usableArea(of: TestDisplays.air)
        for w in [picky, x, y] { XCTAssertTrue(area.insetBy(dx: -1, dy: -1).contains(w.frame), "\(w.title) on screen: \(w.frame)") }
    }

    // MARK: overflow

    func testAWindowThatCannotFitAnywhereIsFloatedCentredAndOnScreen() {
        let h = Harness()
        let a = h.system.existing("a")
        a.minSize = CGSize(width: 1000, height: 0)
        h.start()
        let b = h.system.open("b") { $0.minSize = CGSize(width: 1000, height: 0) }
        let passes = h.settle()
        XCTAssertLessThanOrEqual(passes, 6)

        let area = h.wm.usableArea(of: TestDisplays.air)
        XCTAssertEqual(h.wm.counters.autoFloats, 1)
        XCTAssertTrue(h.wm.isFloating(b.windowID), "the newest overflowing window floats")
        XCTAssertFalse(h.wm.isFloating(a.windowID))
        XCTAssertNotNil(h.wm.autoFloated[b.windowID])
        XCTAssertTrue(area.contains(b.frame), "fully inside the usable area: \(b.frame) in \(area)")
        XCTAssertEqual(b.frame.midX, area.midX, accuracy: 1)
        XCTAssertEqual(b.frame.midY, area.midY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(b.frame.width, 1000)
        XCTAssertTrue(area.contains(a.frame))
        XCTAssertFalse(h.wm.visiblePlacements[a.windowID]!.overflows)

        // Stable afterwards.
        let writes = a.setFrameCount + b.setFrameCount
        for _ in 0..<5 {
            h.wm.setNeedsLayout()
            h.settle()
        }
        XCTAssertEqual(a.setFrameCount + b.setFrameCount, writes)
        XCTAssertEqual(h.wm.counters.autoFloats, 1)
    }

    func testClosingTheOverflowingNeighbourLeavesTheFloatAlone() {
        let h = Harness()
        let a = h.system.existing("a")
        a.minSize = CGSize(width: 1000, height: 0)
        h.start()
        let b = h.system.open("b") { $0.minSize = CGSize(width: 1000, height: 0) }
        h.settle()
        XCTAssertTrue(h.wm.isFloating(b.windowID))
        h.system.destroy(a.windowID)
        h.settle()
        XCTAssertTrue(h.wm.isFloating(b.windowID), "an auto-floated window stays floating")
        XCTAssertTrue(h.wm.usableArea(of: TestDisplays.air).contains(b.frame))
    }
}
