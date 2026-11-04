import XCTest
import CoreGraphics
import CaelestiaCore
@testable import CaelestiaShell

/// Frame band wrapping hardware cutouts, and the layout helpers that depend on them.
final class CutoutFrameTests: XCTestCase {
    let outer = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let insets = Insets.uniform(10)
    // A notch at the top centre, 32 tall, y-down.
    let notch = CGRect(x: 420, y: 0, width: 160, height: 32)

    func filled(_ p: CGPath, _ x: Double, _ y: Double) -> Bool {
        p.contains(CGPoint(x: x, y: y), using: .evenOdd)
    }

    func testPathWithoutCutoutsIsTheOldBand() {
        let p = FramePath.path(outer: outer, insets: insets, radius: 20, cutouts: [], thickness: 10)
        XCTAssertTrue(filled(p, 500, 5), "top band")
        XCTAssertTrue(filled(p, 5, 300), "left band")
        XCTAssertFalse(filled(p, 500, 300), "interior")
        XCTAssertFalse(filled(p, 500, 40))
        let old = FramePath.path(outer: outer, insets: insets, radius: 20)
        XCTAssertEqual(old.boundingBoxOfPath, p.boundingBoxOfPath)
        for pt in [CGPoint(x: 500, y: 5), CGPoint(x: 500, y: 300), CGPoint(x: 12, y: 12), CGPoint(x: 995, y: 595)] {
            XCTAssertEqual(old.contains(pt, using: .evenOdd), p.contains(pt, using: .evenOdd))
        }
    }

    func testBandDipsAroundCutout() {
        let p = FramePath.path(outer: outer, insets: insets, radius: 20, cutouts: [notch], thickness: 10)
        // Dip goes to 32 + 10 = 42 below the top, cutout widened by 10 each side.
        XCTAssertTrue(filled(p, 500, 36), "just under the notch, inside the dip")
        XCTAssertTrue(filled(p, 500, 20))
        XCTAssertFalse(filled(p, 500, 100), "well below the dip")
        XCTAssertFalse(filled(p, 300, 25), "away from the notch the band is plain")
        XCTAssertTrue(filled(p, 300, 5))
        XCTAssertFalse(filled(p, 500, 300))
        XCTAssertTrue(filled(p, 5, 300))
    }

    func testCutoutShallowerThanBandChangesNothing() {
        let tiny = CGRect(x: 420, y: 0, width: 160, height: 0)
        let p = FramePath.path(outer: outer, insets: insets, radius: 20, cutouts: [tiny], thickness: 0)
        XCTAssertFalse(filled(p, 500, 20))
        XCTAssertTrue(filled(p, 500, 5))
    }

    func testDipsMergeOverlappingCutouts() {
        let inner = FramePath.inner(of: outer, insets: insets)
        let a = CGRect(x: 100, y: 0, width: 100, height: 32)
        let b = CGRect(x: 205, y: 0, width: 100, height: 32)
        XCTAssertEqual(FramePath.dips(cutouts: [a, b], inner: inner, thickness: 10).count, 1)
        let far = CGRect(x: 700, y: 0, width: 100, height: 32)
        XCTAssertEqual(FramePath.dips(cutouts: [a, far], inner: inner, thickness: 10).count, 2)
    }

    // MARK: DisplayLayout (AppKit bottom-left)

    func layout(cutouts: [CGRect]) -> DisplayLayout {
        // area 1000x600 at origin (0,0); top is y = 600.
        DisplayLayout(area: CGRect(x: 0, y: 0, width: 1000, height: 600), thickness: 10, barWidth: 50,
                      topExtra: 0, cutouts: cutouts)
    }

    func testLocalCutoutsAreYDown() {
        let l = layout(cutouts: [CGRect(x: 420, y: 568, width: 160, height: 32)])
        XCTAssertEqual(l.localCutouts, [CGRect(x: 420, y: 0, width: 160, height: 32)])
        let shifted = DisplayLayout(area: CGRect(x: 100, y: 50, width: 1000, height: 600), thickness: 10, barWidth: 50,
                                    cutouts: [CGRect(x: 520, y: 618, width: 160, height: 32)])
        XCTAssertEqual(shifted.localCutouts, [CGRect(x: 420, y: 0, width: 160, height: 32)])
    }

    func testTopClearance() {
        let l = layout(cutouts: [CGRect(x: 420, y: 568, width: 160, height: 32)])
        XCTAssertEqual(l.topClearance(minX: 0, maxX: 100), 0)
        XCTAssertEqual(l.topClearance(minX: 600, maxX: 900), 0)
        // bandBottom = 600 - 10 = 590; cutout.minY - thickness = 558 → 32.
        XCTAssertEqual(l.topClearance(minX: 400, maxX: 450), 32)
        XCTAssertEqual(layout(cutouts: []).topClearance(minX: 0, maxX: 1000), 0)
    }

    func testBarFrameUnaffectedByFarCutout() {
        let plain = layout(cutouts: [])
        let notched = layout(cutouts: [CGRect(x: 420, y: 568, width: 160, height: 32)])
        XCTAssertEqual(notched.barFrame, plain.barFrame)
        XCTAssertEqual(plain.barFrame, CGRect(x: 0, y: 0, width: 50, height: 600))
        let overlapping = layout(cutouts: [CGRect(x: 0, y: 568, width: 100, height: 32)])
        XCTAssertLessThan(overlapping.barFrame.height, 600)
    }

    func testDefaultInitHasNoCutouts() {
        let l = DisplayLayout(area: CGRect(x: 0, y: 0, width: 100, height: 100), thickness: 5, barWidth: 20)
        XCTAssertEqual(l.cutouts, [])
        XCTAssertEqual(l.topExtra, 0)
    }
}
