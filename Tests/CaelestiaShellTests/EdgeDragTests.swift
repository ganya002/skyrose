import CoreGraphics
import XCTest

@testable import CaelestiaShell

final class EdgeDragTests: XCTestCase {
    let layout = DisplayLayout(area: CGRect(x: 0, y: 0, width: 1470, height: 956), thickness: 10, barWidth: 60, topExtra: 33)
    let sessionH = 400.0

    func zone(_ x: Double, _ y: Double) -> EdgeDrag.Zone? {
        EdgeDrag.zone(at: CGPoint(x: x, y: y), layout: layout, barReveal: 0, sessionHeight: sessionH)
    }

    func testZones() {
        let inner = layout.inner(barReveal: 0)
        XCTAssertEqual(zone(1469, inner.midY), .session)
        XCTAssertEqual(zone(1465, inner.midY + 150), .session)
        XCTAssertEqual(zone(1465, inner.minY + 20), .sidebar)
        XCTAssertEqual(zone(1465, inner.maxY - 20), .sidebar)
        XCTAssertNil(zone(1400, inner.midY), "inside the tiles is not the edge")
        XCTAssertNil(zone(5, inner.midY), "left edge is the bar's")
        XCTAssertNil(zone(1469, layout.area.maxY), "above the inner area (menu bar strip)")
    }

    func testSessionOpensPast30() {
        var d = EdgeDrag()
        d.begin(at: CGPoint(x: 1468, y: 480), zone: .session)
        XCTAssertNil(d.drag(to: CGPoint(x: 1450, y: 482)))
        XCTAssertEqual(d.drag(to: CGPoint(x: 1437, y: 485)), .session)
        XCTAssertNil(d.drag(to: CGPoint(x: 1300, y: 485)), "fires once")
    }

    func testSidebarNeeds80() {
        var d = EdgeDrag()
        d.begin(at: CGPoint(x: 1468, y: 100), zone: .sidebar)
        XCTAssertNil(d.drag(to: CGPoint(x: 1420, y: 100)))
        XCTAssertEqual(d.drag(to: CGPoint(x: 1387, y: 110)), .sidebar)
    }

    func testOutsideZoneOrVerticalDragDoesNothing() {
        var d = EdgeDrag()
        d.begin(at: CGPoint(x: 700, y: 400), zone: nil)
        XCTAssertNil(d.drag(to: CGPoint(x: 100, y: 400)))
        d.begin(at: CGPoint(x: 1468, y: 480), zone: .session)
        XCTAssertNil(d.drag(to: CGPoint(x: 1460, y: 700)), "a vertical drag cancels")
        XCTAssertNil(d.drag(to: CGPoint(x: 1300, y: 480)))
        d.begin(at: CGPoint(x: 1468, y: 480), zone: .session)
        d.end()
        XCTAssertNil(d.drag(to: CGPoint(x: 1300, y: 480)), "mouse up ends it")
        d.begin(at: CGPoint(x: 1468, y: 480), zone: .session)
        XCTAssertNil(d.drag(to: CGPoint(x: 1500, y: 480)), "rightwards opens nothing")
    }

    func testSwipe() {
        var d = EdgeDrag()
        d.begin(at: CGPoint(x: 1468, y: 480), zone: .session)
        XCTAssertNil(d.swipe(fingerDX: -12, fingerDY: 1))
        XCTAssertNil(d.swipe(fingerDX: -12, fingerDY: 0))
        XCTAssertEqual(d.swipe(fingerDX: -10, fingerDY: 0), .session)
        d.begin(at: CGPoint(x: 1468, y: 480), zone: .session)
        XCTAssertNil(d.swipe(fingerDX: -2, fingerDY: -60), "a vertical scroll is not a swipe")
        XCTAssertNil(d.swipe(fingerDX: -60, fingerDY: 0))
    }

    func testFingerDelta() {
        XCTAssertEqual(EdgeDrag.fingerDelta(scrollingDeltaX: -5, invertedFromDevice: true), -5, "natural scrolling follows the fingers")
        XCTAssertEqual(EdgeDrag.fingerDelta(scrollingDeltaX: 5, invertedFromDevice: false), -5)
    }
}
