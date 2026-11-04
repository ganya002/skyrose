import CaelestiaCore
import CoreGraphics
import XCTest

@testable import CaelestiaLayout

/// Learned minimum sizes in the dwindle layout: the split gives the needy side room instead of
/// clipping it over its neighbour, and flags `overflows` when nothing can make it fit.
final class MinSizeLayoutTests: XCTestCase {
    let area = CGRect(x: 10, y: 10, width: 1450, height: 936)

    func tree(_ count: Int) -> DwindleTree {
        var t = DwindleTree()
        for i in 1...count { t.insert(WindowID(i), relativeTo: i > 1 ? WindowID(i - 1) : nil, in: area) }
        return t
    }

    func layout(_ t: DwindleTree, _ mins: [WindowID: CGSize]) -> [WindowID: Placement] {
        Dictionary(uniqueKeysWithValues: t.layout(area: area, params: LayoutParams(), minSizes: mins).map { ($0.window, $0) })
    }

    // MARK: minimumAwareFirstSize

    func testFirstSizeKeepsTheStoredRatioWhenNothingIsNeeded() {
        XCTAssertEqual(DwindleTree.minimumAwareFirstSize(total: 1000, ratio: 1, firstNeeds: 0, secondNeeds: 0), 500)
        XCTAssertEqual(DwindleTree.minimumAwareFirstSize(total: 1000, ratio: 1.2, firstNeeds: 0, secondNeeds: 0), 600)
    }

    func testFirstSizeKeepsTheRatioWhenBothSidesFitAlready() {
        XCTAssertEqual(DwindleTree.minimumAwareFirstSize(total: 1000, ratio: 1, firstNeeds: 300, secondNeeds: 300), 500)
    }

    func testFirstSizeGrowsForTheFirstSideThatNeedsMore() {
        XCTAssertEqual(DwindleTree.minimumAwareFirstSize(total: 1000, ratio: 1, firstNeeds: 600, secondNeeds: 0), 600)
        XCTAssertEqual(DwindleTree.minimumAwareFirstSize(total: 1000, ratio: 1, firstNeeds: 600, secondNeeds: 300), 600)
    }

    func testFirstSizeShrinksWhenTheSecondSideNeedsMore() {
        XCTAssertEqual(DwindleTree.minimumAwareFirstSize(total: 1000, ratio: 1, firstNeeds: 0, secondNeeds: 700), 300)
        XCTAssertEqual(DwindleTree.minimumAwareFirstSize(total: 1000, ratio: 1, firstNeeds: 200, secondNeeds: 700), 300)
    }

    func testFirstSizeIsProportionalWhenNeitherSideFits() {
        XCTAssertEqual(DwindleTree.minimumAwareFirstSize(total: 1000, ratio: 1, firstNeeds: 800, secondNeeds: 400), 1000 * 800 / 1200, accuracy: 1e-9)
        XCTAssertEqual(DwindleTree.minimumAwareFirstSize(total: 1000, ratio: 1, firstNeeds: 600, secondNeeds: 600), 500, accuracy: 1e-9)
    }

    // MARK: layout

    func testFirstWindowNeedingRoomTakesItFromTheSecond() throws {
        let t = tree(2)
        let plain = layout(t, [:])
        let big = CGSize(width: plain[1]!.frame.width + 150, height: 0)
        let p = layout(t, [1: big])
        XCTAssertGreaterThanOrEqual(p[1]!.frame.width, big.width)
        XCTAssertLessThan(p[2]!.frame.width, plain[2]!.frame.width)
        XCTAssertFalse(p[1]!.frame.intersects(p[2]!.frame))
        XCTAssertFalse(p[1]!.overflows)
        XCTAssertFalse(p[2]!.overflows)
        // The two columns still cover the same span as before.
        XCTAssertEqual(p[2]!.frame.maxX, plain[2]!.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(p[1]!.frame.minX, plain[1]!.frame.minX, accuracy: 0.5)
    }

    func testSecondWindowNeedingRoomTakesItFromTheFirst() {
        let t = tree(2)
        let plain = layout(t, [:])
        let p = layout(t, [2: CGSize(width: plain[2]!.frame.width + 200, height: 0)])
        XCTAssertGreaterThanOrEqual(p[2]!.frame.width, plain[2]!.frame.width + 200)
        XCTAssertLessThan(p[1]!.frame.width, plain[1]!.frame.width)
        XCTAssertFalse(p[1]!.frame.intersects(p[2]!.frame))
        XCTAssertFalse(p.values.contains { $0.overflows })
    }

    func testMinimumsOfOtherWindowsAreIgnored() {
        let t = tree(2)
        XCTAssertEqual(layout(t, [99: CGSize(width: 5000, height: 5000)]), layout(t, [:]))
    }

    func testVerticalSplitGivesHeight() {
        let t = tree(3)  // 3 sits in the second column, split vertically with 2
        let plain = layout(t, [:])
        let need = plain[2]!.frame.height + 150
        let p = layout(t, [2: CGSize(width: 0, height: need)])
        XCTAssertGreaterThanOrEqual(p[2]!.frame.height, need)
        XCTAssertLessThan(p[3]!.frame.height, plain[3]!.frame.height)
        XCTAssertFalse(p[2]!.frame.intersects(p[3]!.frame))
        XCTAssertFalse(p.values.contains { $0.overflows })
    }

    func testBothTooBigIsProportionalAndFlagsOverflow() {
        let t = tree(2)
        let p = layout(t, [1: CGSize(width: 1000, height: 0), 2: CGSize(width: 1000, height: 0)])
        XCTAssertTrue(p[1]!.overflows || p[2]!.overflows)
        for w in [1, 2] as [WindowID] {
            XCTAssertGreaterThanOrEqual(p[w]!.frame.width, 1000, "the frame always carries at least the min size")
        }
    }

    func testSingleWindowBiggerThanTheAreaOverflows() {
        let t = tree(1)
        let p = layout(t, [1: CGSize(width: 3000, height: 0)])
        XCTAssertTrue(p[1]!.overflows)
        XCTAssertEqual(p[1]!.frame.width, 3000)
    }

    func testFittingMinimumDoesNotOverflow() {
        let t = tree(1)
        XCTAssertFalse(layout(t, [1: CGSize(width: 800, height: 600)])[1]!.overflows)
        XCTAssertFalse(layout(tree(2), [1: CGSize(width: 800, height: 600)])[1]!.overflows)
    }

    func testLayoutWithMinimumsIsStableAcrossPasses() {
        let t = tree(4)
        let mins: [WindowID: CGSize] = [1: CGSize(width: 900, height: 0), 3: CGSize(width: 0, height: 500)]
        let first = t.layout(area: area, params: LayoutParams(), minSizes: mins)
        for _ in 0..<5 { XCTAssertEqual(t.layout(area: area, params: LayoutParams(), minSizes: mins), first) }
    }
}
