import CoreGraphics
import XCTest

@testable import CaelestiaShell

/// Caelestia's hover reveals (Interactions.qml): top band → dashboard, bottom-right corner →
/// utilities, right band → OSD; open drawers keep their zone while the pointer is on them.
final class HoverRevealTests: XCTestCase {
    // A 1470×956 display, 10 pt frame, hidden bar (AppKit space).
    let layout = DisplayLayout(area: CGRect(x: 0, y: 0, width: 1470, height: 924), thickness: 10, barWidth: 60)
    let sizes = HoverReveal.Sizes(dashboard: CGSize(width: 800, height: 400), utilities: CGSize(width: 380, height: 330),
                                  osd: CGSize(width: 80, height: 300))

    func hit(_ x: Double, _ y: Double, _ t: HoverReveal.Target, open: Bool = false) -> Bool {
        HoverReveal.contains(CGPoint(x: x, y: y), target: t, layout: layout, barReveal: 0, sizes: sizes, rounding: 25, open: open)
    }

    func testTopBandOverTheDashboardWidthRevealsIt() {
        XCTAssertTrue(hit(735, 920, .dashboard), "top band, centre")
        XCTAssertTrue(hit(735, 924, .dashboard), "the very edge")
        XCTAssertTrue(hit(735 - 400 - 24, 918, .dashboard), "within rounding of the drawer's side")
        XCTAssertFalse(hit(735 - 400 - 30, 918, .dashboard), "outside the drawer's width")
        XCTAssertFalse(hit(735, 900, .dashboard), "below the band (over windows)")
    }

    func testTheNotchDipCountsAsTopBand() {
        // A 190×32 notch centred at the top: the band wraps it down to 32 + 10 below the top.
        let notched = DisplayLayout(area: CGRect(x: 0, y: 0, width: 1470, height: 956), thickness: 10, barWidth: 60,
                                    cutouts: [CGRect(x: 640, y: 924, width: 190, height: 32)])
        func at(_ x: Double, _ y: Double) -> Bool {
            HoverReveal.contains(CGPoint(x: x, y: y), target: .dashboard, layout: notched, barReveal: 0, sizes: sizes, rounding: 25, open: false)
        }
        XCTAssertTrue(at(735, 956 - 37), "in the dip under the notch")
        XCTAssertTrue(at(500, 956 - 4), "plain band beside the notch")
        XCTAssertFalse(at(735, 956 - 50), "below the dip")
    }

    func testAnOpenDashboardKeepsItsZoneUntilThePointerLeaves() {
        XCTAssertTrue(hit(735, 600, .dashboard, open: true), "on the drawer")
        XCTAssertTrue(hit(735, 914 - 400 - 20, .dashboard, open: true), "within rounding below it")
        XCTAssertFalse(hit(735, 914 - 400 - 30, .dashboard, open: true), "left it downwards")
        XCTAssertFalse(hit(200, 800, .dashboard, open: true), "left it sideways")
    }

    func testBottomRightCornerRevealsUtilities() {
        XCTAssertTrue(hit(1465, 5, .utilities), "the corner")
        XCTAssertTrue(hit(1460 - 370, 5, .utilities), "bottom band under the column")
        XCTAssertFalse(hit(1460 - 390, 5, .utilities), "bottom band left of the column")
        XCTAssertFalse(hit(1300, 30, .utilities), "above the band: no reveal while working")
        XCTAssertTrue(hit(1300, 300, .utilities, open: true), "on the open drawer")
        XCTAssertFalse(hit(1300, 10 + 330 + 30, .utilities, open: true), "left it upwards")
    }

    func testRightBandOverTheOSDHeightRevealsIt() {
        XCTAssertTrue(hit(1465, 462, .osd))
        XCTAssertTrue(hit(1465, 462 + 150 + 20, .osd), "within rounding of its height")
        XCTAssertFalse(hit(1465, 462 + 150 + 30, .osd))
        XCTAssertFalse(hit(1440, 462, .osd), "left of the band while closed")
        XCTAssertTrue(hit(1400, 462, .osd, open: true), "on the open OSD")
    }

    func testCornerDrawerPathSitsOnBothBands() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 200)
        let path = CornerDrawerPath.bottomRight(in: rect, radius: 25, fillet: 25)
        let box = path.boundingBoxOfPath
        for (a, b) in [(box.minX, rect.minX), (box.minY, rect.minY), (box.maxX, rect.maxX), (box.maxY, rect.maxY)] {
            XCTAssertEqual(a, b, accuracy: 1e-9)
        }
        XCTAssertTrue(path.contains(CGPoint(x: 299, y: 199)), "bottom-right corner on the bands")
        XCTAssertTrue(path.contains(CGPoint(x: 150, y: 100)), "body")
        XCTAssertFalse(path.contains(CGPoint(x: 27, y: 27)), "rounded free corner")
        XCTAssertFalse(path.contains(CGPoint(x: 5, y: 150)), "left of the body above the bottom fillet")
        // The fillets are concave quarter circles centred at (0, h − f) and (w − f, 0).
        XCTAssertTrue(path.contains(CGPoint(x: 20, y: 198)), "bottom fillet flares onto the band")
        XCTAssertFalse(path.contains(CGPoint(x: 3, y: 190)), "inside the bottom fillet's circle")
        XCTAssertTrue(path.contains(CGPoint(x: 298, y: 20)), "right fillet flares onto the band")
        XCTAssertFalse(path.contains(CGPoint(x: 290, y: 3)), "inside the right fillet's circle")
        XCTAssertFalse(path.contains(CGPoint(x: 150, y: 5)), "above the body, left of the right fillet")
    }
}
