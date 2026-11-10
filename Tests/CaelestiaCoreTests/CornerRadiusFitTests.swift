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

    /// A window with antialiased round corners, the way a capture returns one.
    private func roundedWindow(radius r: Double, width: Int, height: Int) -> [UInt8] {
        var alpha = [UInt8](repeating: 0, count: width * height)
        let w = Double(width), h = Double(height)
        for y in 0..<height {
            for x in 0..<width {
                var hits = 0
                for sy in 0..<4 {
                    for sx in 0..<4 {
                        let px = Double(x) + (Double(sx) + 0.5) / 4, py = Double(y) + (Double(sy) + 0.5) / 4
                        let dx = max(r - px, px - (w - r), 0), dy = max(r - py, py - (h - r), 0)
                        if dx * dx + dy * dy <= r * r { hits += 1 }
                    }
                }
                alpha[y * width + x] = UInt8(hits * 255 / 16)
            }
        }
        return alpha
    }

    func testAMeasuredWindowGetsItsRealRadiusInPoints() throws {
        let alpha = roundedWindow(radius: 48, width: 400, height: 300)
        let radii = try XCTUnwrap(CornerRadiusFit.radii(alpha: alpha, width: 400, height: 300, scale: 2))
        for value in [radii.topLeft, radii.topRight, radii.bottomRight, radii.bottomLeft] {
            XCTAssertEqual(value, 24, accuracy: 0.75)
        }
    }

    func testAMeasuredSquareWindowStaysSquare() throws {
        let alpha = [UInt8](repeating: 255, count: 100 * 80)
        XCTAssertEqual(try XCTUnwrap(CornerRadiusFit.radii(alpha: alpha, width: 100, height: 80, scale: 1)), .square)
    }

    func testAWindowWithNothingDrawnIsNotCalledSquare() {
        let alpha = [UInt8](repeating: 0, count: 100 * 80)
        XCTAssertNil(CornerRadiusFit.radii(alpha: alpha, width: 100, height: 80, scale: 1))
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
