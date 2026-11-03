import XCTest
import CoreGraphics
import CaelestiaCore
@testable import CaelestiaLayout

/// Tree operations from spec 12.1: removal, swapping, preserve_split, ratios, resize ±10, min-size
/// clipping, groups.
final class DwindleOperationTests: XCTestCase {
    let area = CGRect(x: 10, y: 10, width: 1450, height: 936)

    func tree(_ count: Int) -> DwindleTree {
        var t = DwindleTree()
        for i in 1...count { t.insert(WindowID(i), relativeTo: i > 1 ? WindowID(i - 1) : nil, in: area) }
        return t
    }

    func frame(_ t: DwindleTree, _ w: WindowID, minSizes: [WindowID: CGSize] = [:]) -> CGRect? {
        t.layout(area: area, params: LayoutParams(), minSizes: minSizes).first { $0.window == w }?.frame
    }

    func testInsertIntoEmptyTreeMakesRoot() {
        var t = DwindleTree()
        XCTAssertTrue(t.insert(7, in: area))
        XCTAssertFalse(t.insert(7, in: area), "duplicate insert is refused")
        XCTAssertEqual(t.windows, [7])
    }

    func testRemovingCollapsesParentSoSiblingTakesItsBox() {
        var t = tree(3)
        let before = frame(t, 2)
        XCTAssertTrue(t.remove(3))
        XCTAssertFalse(t.remove(3))
        XCTAssertEqual(t.windows, [1, 2])
        XCTAssertNotEqual(frame(t, 2), before)
        XCTAssertEqual(frame(t, 2), frame(tree(2), 2))
    }

    func testRemovingEverythingEmptiesTheTree() {
        var t = tree(2)
        t.remove(1)
        t.remove(2)
        XCTAssertTrue(t.isEmpty)
    }

    func testSwapExchangesSlots() {
        var t = tree(2)
        let f1 = frame(t, 1), f2 = frame(t, 2)
        XCTAssertTrue(t.swap(1, 2))
        XCTAssertEqual(frame(t, 1), f2)
        XCTAssertEqual(frame(t, 2), f1)
    }

    func testMoveSwapsWithGeometricNeighbour() {
        var t = tree(2)
        XCTAssertEqual(t.neighbor(of: 1, direction: .right, in: area), 2)
        XCTAssertNil(t.neighbor(of: 1, direction: .left, in: area))
        let f2 = frame(t, 2)
        XCTAssertTrue(t.move(1, .right, in: area))
        XCTAssertEqual(frame(t, 1), f2)
        XCTAssertFalse(t.move(1, .right, in: area), "nothing further right")
    }

    func testToggleSplitIsPreserved() {
        var t = tree(2)
        XCTAssertTrue(t.toggleSplit(2))
        // Now stacked: same x, different y.
        let f1 = frame(t, 1)!, f2 = frame(t, 2)!
        XCTAssertEqual(f1.minX, f2.minX)
        XCTAssertLessThan(f1.maxY, f2.minY)
        var single = tree(1)
        XCTAssertFalse(single.toggleSplit(1), "root has no parent split")
    }

    func testSplitRatioClampsToHyprlandRange() {
        var t = tree(2)
        XCTAssertTrue(t.setSplitRatio(1, 5, exact: true))
        let wide = frame(t, 1)!
        XCTAssertTrue(t.setSplitRatio(1, 1.9, exact: true))
        XCTAssertEqual(frame(t, 1), wide, "5 clamps to 1.9")
        XCTAssertGreaterThan(wide.width, frame(tree(2), 1)!.width)
    }

    func testKeyboardResizeGrowsTheWindowByDeltaWithSmartResizing() throws {
        var t = tree(2)
        let w1 = try XCTUnwrap(frame(t, 1)).width
        let w2 = try XCTUnwrap(frame(t, 2)).width
        XCTAssertTrue(t.resize(2, axis: .width, delta: 10, in: area))
        XCTAssertEqual(frame(t, 2)!.width, w2 + 10, accuracy: 1)
        XCTAssertEqual(frame(t, 1)!.width, w1 - 10, accuracy: 1)
        XCTAssertTrue(t.resize(2, axis: .width, delta: -10, in: area))
        XCTAssertEqual(frame(t, 2)!.width, w2, accuracy: 1)
        XCTAssertFalse(t.resize(2, axis: .height, delta: 10, in: area), "no vertical split above it")
    }

    func testMinSizeClipsCentredWithoutChangingNeighbours() throws {
        let t = tree(2)
        let slot = try XCTUnwrap(frame(t, 1))
        let big = CGSize(width: slot.width + 100, height: slot.height)
        let clipped = try XCTUnwrap(frame(t, 1, minSizes: [1: big]))
        XCTAssertEqual(clipped.size, big)
        XCTAssertEqual(clipped.midX, slot.midX, accuracy: 0.5)
        XCTAssertEqual(frame(t, 2, minSizes: [1: big]), frame(t, 2))
        // Converges: the same inputs give the same output on every pass.
        XCTAssertEqual(t.layout(area: area, params: LayoutParams(), minSizes: [1: big]),
                       t.layout(area: area, params: LayoutParams(), minSizes: [1: big]))
    }

    func testGroupsHideInactiveTabs() {
        var t = tree(2)
        XCTAssertTrue(t.groupToggle(1, in: area))
        XCTAssertTrue(t.groupAdd(2, to: 1))
        XCTAssertEqual(t.groupMembers(of: 1), [1, 2])
        XCTAssertEqual(t.leafCount, 1)
        let p = t.layout(area: area, params: LayoutParams())
        XCTAssertEqual(p.filter { !$0.hidden }.count, 1)
        let active = t.groupActiveWindow(of: 1)
        XCTAssertNotNil(t.groupNext(in: 1))
        XCTAssertNotEqual(t.groupActiveWindow(of: 1), active)
    }

    func testLockedGroupRejectsAutoGroup() {
        var t = tree(1)
        t.groupToggle(1, in: area)
        t.groupSetLocked(1, true)
        XCTAssertTrue(t.isGroupLocked(1))
        t.insert(2, relativeTo: 1, in: area)
        XCTAssertEqual(t.leafCount, 2, "locked group: the new window splits instead of joining")
    }
}
