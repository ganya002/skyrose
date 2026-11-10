import CoreGraphics
import XCTest

@testable import CaelestiaCore

final class CursorWarpTests: XCTestCase {
    let frame = CGRect(x: 100, y: 40, width: 200, height: 100)

    func testCentreIsTheMiddle() {
        let point = CursorWarp.destination(
            frame: frame, mode: .center, lastInside: CGPoint(x: 110, y: 50), cursor: CGPoint(x: 1, y: 1),
            mouseDown: false, dragging: false, enabled: true, onVisibleDisplay: true)
        XCTAssertEqual(point, CGPoint(x: 200, y: 90))
    }

    func testLastUsesTheRememberedPointInsideTheWindow() {
        let last = CGPoint(x: 120, y: 55)
        let point = CursorWarp.destination(
            frame: frame, mode: .last, lastInside: last, cursor: nil,
            mouseDown: false, dragging: false, enabled: true, onVisibleDisplay: true)
        XCTAssertEqual(point, last)
    }

    func testLastFallsBackToCentre() {
        let point = CursorWarp.destination(
            frame: frame, mode: .last, lastInside: CGPoint(x: 1, y: 1), cursor: nil,
            mouseDown: false, dragging: false, enabled: true, onVisibleDisplay: true)
        XCTAssertEqual(point, CGPoint(x: 200, y: 90))
    }

    func testAPointerAlreadyInsideDoesNotWarp() {
        let point = CursorWarp.destination(
            frame: frame, mode: .center, lastInside: nil, cursor: CGPoint(x: 150, y: 60),
            mouseDown: false, dragging: false, enabled: true, onVisibleDisplay: true)
        XCTAssertNil(point)
    }

    func testAHeldButtonADragOrAHiddenDisplayDoesNotWarp() {
        let base = CGPoint?.none
        XCTAssertNil(CursorWarp.destination(frame: frame, mode: .center, lastInside: nil, cursor: base, mouseDown: true, dragging: false, enabled: true, onVisibleDisplay: true))
        XCTAssertNil(CursorWarp.destination(frame: frame, mode: .center, lastInside: nil, cursor: base, mouseDown: false, dragging: true, enabled: true, onVisibleDisplay: true))
        XCTAssertNil(CursorWarp.destination(frame: frame, mode: .center, lastInside: nil, cursor: base, mouseDown: false, dragging: false, enabled: false, onVisibleDisplay: true))
        XCTAssertNil(CursorWarp.destination(frame: frame, mode: .center, lastInside: nil, cursor: base, mouseDown: false, dragging: false, enabled: true, onVisibleDisplay: false))
    }
}
