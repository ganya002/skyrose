@testable import CaelestiaPlatform
import CoreGraphics
import XCTest

final class PointerHitTests: XCTestCase {
    private let back = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let spot = CGPoint(x: 200, y: 200)

    private func window(_ id: CGWindowID, _ bounds: CGRect, layer: Int = 0, alpha: Double = 1, owner: String = "App") -> CGWindowSnapshot {
        CGWindowSnapshot(id: id, pid: 42, layer: layer, bounds: bounds, alpha: alpha, ownerName: owner)
    }

    func testTheFrontWindowWinsOverAnOverlappingOneBehind() {
        let stack = [window(2, back), window(1, back)]
        XCTAssertEqual(CGWindowSnapshot.hit(at: spot, stack: stack), .window(2))
    }

    func testOrderNotIdDecidesWhenALowerIdFloatsOnTop() {
        let float = CGRect(x: 100, y: 100, width: 300, height: 300)
        XCTAssertEqual(CGWindowSnapshot.hit(at: spot, stack: [window(1, float), window(9, back)]), .window(1))
        XCTAssertEqual(CGWindowSnapshot.hit(at: CGPoint(x: 700, y: 500), stack: [window(1, float), window(9, back)]), .window(9))
    }

    func testAFullyTransparentWindowIsLookedThrough() {
        XCTAssertEqual(CGWindowSnapshot.hit(at: spot, stack: [window(2, back, alpha: 0), window(1, back)]), .window(1))
    }

    func testMenusPopoversAndTheDockBlock() {
        let menu = CGRect(x: 150, y: 150, width: 200, height: 200)
        XCTAssertEqual(CGWindowSnapshot.hit(at: spot, stack: [window(5, menu, layer: 101), window(1, back)]), .blocked)
        XCTAssertEqual(CGWindowSnapshot.hit(at: spot, stack: [window(6, menu, layer: 20, owner: "Dock"), window(1, back)]), .blocked)
        XCTAssertEqual(CGWindowSnapshot.hit(at: spot, stack: [window(7, menu, layer: 3), window(1, back)]), .blocked)
    }

    func testSpotlightBlocksAtAnyLayer() {
        XCTAssertEqual(CGWindowSnapshot.hit(at: spot, stack: [window(5, back, layer: 30, owner: "Spotlight"), window(1, back)]), .blocked)
    }

    func testANearlyFullScreenOverlayIsNotUI() {
        let cover = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let stack = [window(5, cover, layer: 26, owner: "Hex"), window(6, cover, layer: 20), window(1, back)]
        XCTAssertEqual(CGWindowSnapshot.hit(at: spot, stack: stack, displayArea: 1000 * 800), .window(1))
    }

    func testAnUnrelatedHighLayerAppWindowIsLookedThrough() {
        let small = CGRect(x: 150, y: 150, width: 100, height: 100)
        XCTAssertEqual(CGWindowSnapshot.hit(at: spot, stack: [window(5, small, layer: 27, owner: "Hex"), window(1, back)]), .window(1))
    }

    func testTheWindowServerIndicatorIsIgnored() {
        let small = CGRect(x: 190, y: 190, width: 28, height: 28)
        XCTAssertEqual(CGWindowSnapshot.hit(at: spot, stack: [window(5, small, layer: 2147483630, owner: "Window Server"), window(1, back)]), .window(1))
    }

    func testTheBorderStripDoesNotReachTheWindowBehind() {
        let float = CGRect(x: 100, y: 100, width: 300, height: 300)
        let onBorder = CGPoint(x: 99, y: 200)
        XCTAssertEqual(CGWindowSnapshot.hit(at: onBorder, stack: [window(1, float), window(9, back)], borderWidth: 2), .blocked)
        XCTAssertEqual(CGWindowSnapshot.hit(at: onBorder, stack: [window(1, float), window(9, back)]), .window(9))
    }

    func testTheDesktopIsNothing() {
        XCTAssertEqual(CGWindowSnapshot.hit(at: CGPoint(x: 900, y: 900), stack: [window(1, back)]), .nothing)
    }
}
