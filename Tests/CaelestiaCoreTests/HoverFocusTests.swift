import XCTest

@testable import CaelestiaCore

final class HoverFocusTests: XCTestCase {
    func testHoverFocusesAfterTheDelayAndNotBefore() {
        var hover = HoverFocus()
        XCTAssertNil(hover.update(over: 7, at: 1, delay: 0.1, blocked: nil))
        XCTAssertNil(hover.update(over: 7, at: 1.05, delay: 0.1, blocked: nil))
        XCTAssertEqual(hover.update(over: 7, at: 1.1, delay: 0.1, blocked: nil), 7)
    }

    func testAZeroDelayFocusesImmediately() {
        var hover = HoverFocus()
        XCTAssertEqual(hover.update(over: 3, at: 0, delay: 0, blocked: nil), 3)
    }

    func testLeavingOrABlockForgetsTheCandidate() {
        var hover = HoverFocus()
        _ = hover.update(over: 4, at: 0, delay: 0.2, blocked: nil)
        XCTAssertNil(hover.update(over: nil, at: 0.3, delay: 0.2, blocked: nil))
        XCTAssertNil(hover.update(over: 4, at: 0.3, delay: 0.2, blocked: .sheet))
        XCTAssertNil(hover.update(over: 4, at: 1, delay: 0.2, blocked: nil), "the wait starts again after the block")
        XCTAssertEqual(hover.update(over: 4, at: 1.2, delay: 0.2, blocked: nil), 4)
    }

    func testMovingToAnotherWindowRestartsTheWait() {
        var hover = HoverFocus()
        _ = hover.update(over: 1, at: 0, delay: 0.1, blocked: nil)
        XCTAssertNil(hover.update(over: 2, at: 0.09, delay: 0.1, blocked: nil))
        XCTAssertEqual(hover.update(over: 2, at: 0.19, delay: 0.1, blocked: nil), 2)
    }
}
