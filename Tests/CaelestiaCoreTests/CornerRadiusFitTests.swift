import XCTest

@testable import CaelestiaCore

final class CornerRadiusFitTests: XCTestCase {
    func testASquareMaskFitsZero() {
        let side = 12
        let mask = CornerRadiusFit.Mask(width: side, height: side, alpha: [UInt8](repeating: 255, count: side * side))
        XCTAssertEqual(CornerRadiusFit.topLeftRadius(mask), 0)
    }

    func testAQuarterCircleFitsItsRadius() {
        for radius in [4, 8, 16, 26] {
            let mask = CornerRadiusFit.quarterCircle(radius: radius, side: radius + 6)
            XCTAssertEqual(CornerRadiusFit.topLeftRadius(mask), Double(radius), "radius \(radius)")
        }
    }

    func testAnEmptyMaskFitsZero() {
        let mask = CornerRadiusFit.Mask(width: 8, height: 8, alpha: [UInt8](repeating: 0, count: 64))
        XCTAssertEqual(CornerRadiusFit.topLeftRadius(mask), 0)
    }

    func testOutsetKeepsASquareCornerSquareAndGrowsARoundOneByTheStroke() {
        XCTAssertEqual(CornerRadii.square.outset(by: 1.5), .square)
        let grown = CornerRadii(uniform: 16).outset(by: 1.5)
        XCTAssertEqual(grown.uniform ?? -1, 17.5, accuracy: 0.001)
    }

    func testUnevenCornersStayInOrder() {
        let radii = CornerRadii(topLeft: 10, topRight: 12, bottomRight: 0, bottomLeft: 8)
        XCTAssertNil(radii.uniform)
        XCTAssertFalse(radii.isSquare)
        let path = radii.outset(by: 2).path(in: CGRect(x: 0, y: 0, width: 100, height: 80))
        XCTAssertFalse(path.isEmpty)
    }
}
