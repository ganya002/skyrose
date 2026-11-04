import XCTest
import CoreGraphics
import CaelestiaCore
@testable import CaelestiaPlatform

/// Hardware cutouts (notch) and the shown-menu-bar facts derived from `ScreenFacts`.
final class DisplayCutoutTests: XCTestCase {
    typealias Facts = DisplayGeometry.ScreenFacts

    func notched(visibleTop: Double = 924, autoHides: Bool = true) -> Facts {
        Facts(
            uuid: "air", frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: visibleTop), safeAreaTop: 32, scale: 2,
            auxiliaryTopLeft: CGRect(x: 0, y: 924, width: 645.5, height: 32),
            auxiliaryTopRight: CGRect(x: 824.5, y: 924, width: 645.5, height: 32),
            menuBarAutoHides: autoHides
        )
    }

    func info(_ f: Facts) -> DisplayInfo {
        DisplayGeometry.displays(from: [f])[0]
    }

    func testNotchedMacBookHasOneCutout() {
        let rects = DisplayGeometry.cutoutRects(notched())
        XCTAssertEqual(rects, [CGRect(x: 645.5, y: 924, width: 179, height: 32)])
        let d = info(notched())
        XCTAssertEqual(d.topCutouts, [CGRect(x: 645.5, y: 0, width: 179, height: 32)])
        XCTAssertEqual(d.shownMenuBarHeight, 0)
        XCTAssertEqual(d.menuBarHeight, 32)
    }

    func testSafeAreaWithoutAuxiliaryAreasBlocksWholeStrip() {
        var f = notched()
        f.auxiliaryTopLeft = nil
        f.auxiliaryTopRight = nil
        XCTAssertEqual(DisplayGeometry.cutoutRects(f), [CGRect(x: 0, y: 924, width: 1470, height: 32)])
        XCTAssertEqual(info(f).topCutouts, [CGRect(x: 0, y: 0, width: 1470, height: 32)])
    }

    func testNoSafeAreaMeansNoCutouts() {
        var f = Facts(uuid: "ext", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                      visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415))
        XCTAssertEqual(DisplayGeometry.cutoutRects(f), [])
        var d = info(f)
        XCTAssertEqual(d.topCutouts, [])
        XCTAssertEqual(d.shownMenuBarHeight, 25)
        f.visibleFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        d = info(f)
        XCTAssertEqual(d.shownMenuBarHeight, 0)
        XCTAssertEqual(d.topCutouts, [])
    }

    func testShownMenuBarOnNotchedDisplay() {
        let d = info(notched(visibleTop: 924, autoHides: false))
        XCTAssertEqual(d.shownMenuBarHeight, 32, "max(topDiff, safeTop)")
        XCTAssertEqual(d.topCutouts, [], "the menu bar covers the notch strip")
        let taller = info(notched(visibleTop: 920, autoHides: false))
        XCTAssertEqual(taller.shownMenuBarHeight, 36)
    }

    func testAutoHiddenNotchedDetectsMenuBarRevealedByTopDiff() {
        let d = info(notched(visibleTop: 920, autoHides: true))
        XCTAssertEqual(d.shownMenuBarHeight, 36)
        XCTAssertEqual(d.topCutouts, [])
    }

    func testTinySliversAreIgnored() {
        var f = notched()
        f.auxiliaryTopLeft = CGRect(x: 0, y: 924, width: 1, height: 32)
        f.auxiliaryTopRight = CGRect(x: 1469, y: 924, width: 1, height: 32)
        // Cut-out is 1..1469; the 1 pt slivers at the edges are below the minimum width.
        XCTAssertEqual(DisplayGeometry.cutoutRects(f), [CGRect(x: 1, y: 924, width: 1468, height: 32)])
        f.auxiliaryTopLeft = CGRect(x: 0, y: 924, width: 700, height: 32)
        f.auxiliaryTopRight = CGRect(x: 701, y: 924, width: 769, height: 32)
        XCTAssertEqual(DisplayGeometry.cutoutRects(f), [], "1 pt gap is rounding noise")
    }

    func testTwoCutouts() {
        var f = notched()
        f.auxiliaryTopLeft = CGRect(x: 100, y: 924, width: 300, height: 32)
        f.auxiliaryTopRight = CGRect(x: 500, y: 924, width: 300, height: 32)
        let rects = DisplayGeometry.cutoutRects(f)
        XCTAssertEqual(rects, [
            CGRect(x: 0, y: 924, width: 100, height: 32),
            CGRect(x: 400, y: 924, width: 100, height: 32),
            CGRect(x: 800, y: 924, width: 670, height: 32),
        ])
    }

    func testAuxiliaryAreaOutsideStripIsIgnored() {
        var f = notched()
        f.auxiliaryTopLeft = CGRect(x: 0, y: 500, width: 645, height: 32)
        f.auxiliaryTopRight = nil
        XCTAssertEqual(DisplayGeometry.cutoutRects(f), [CGRect(x: 0, y: 924, width: 1470, height: 32)])
    }
}
