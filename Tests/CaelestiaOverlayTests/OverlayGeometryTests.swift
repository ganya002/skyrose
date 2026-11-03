import CaelestiaCore
import CoreGraphics
import XCTest

@testable import CaelestiaOverlay

@MainActor
final class OverlayGeometryTests: XCTestCase {
    func testGroupBarTabsFillInnerWidth() {
        let style = OverlayStyle.gabby
        let frame = CGRect(x: 100, y: 200, width: 600, height: 400)
        for n in 1...6 {
            let tabs = GroupBarGeometry.tabs(count: n, in: frame, style: style)
            XCTAssertEqual(tabs.count, n)
            let inner = frame.insetBy(dx: style.borderWidth, dy: style.borderWidth)
            XCTAssertEqual(tabs.first!.minX, inner.minX, accuracy: 1e-9)
            XCTAssertEqual(tabs.last!.maxX, inner.maxX, accuracy: 1e-9)
            for (i, t) in tabs.enumerated() {
                XCTAssertEqual(t.width, tabs[0].width, accuracy: 1e-9)
                XCTAssertEqual(t.height, style.groupBarHeight)
                XCTAssertEqual(t.minY, inner.minY)
                if i > 0 { XCTAssertEqual(t.minX - tabs[i - 1].maxX, style.groupBarGapsIn, accuracy: 1e-9) }
            }
        }
    }

    func testGroupBarZeroTabs() {
        XCTAssertTrue(GroupBarGeometry.tabs(count: 0, in: CGRect(x: 0, y: 0, width: 10, height: 10), style: .gabby).isEmpty)
    }

    func testGabbyStyle() {
        let s = OverlayStyle.gabby
        XCTAssertEqual(s.active.r, 0xba)
        XCTAssertEqual(s.active.g, 0xc5)
        XCTAssertEqual(s.active.b, 0xee)
        XCTAssertEqual(s.active.alpha, Double(0xe6) / 255, accuracy: 1e-3)
        XCTAssertEqual(s.inactive.r, 0xa9)
        XCTAssertEqual(s.inactive.g, 0xaa)
        XCTAssertEqual(s.inactive.b, 0xb5)
        XCTAssertEqual(s.inactive.alpha, Double(0x11) / 255, accuracy: 1e-3)
        XCTAssertEqual(s.cornerRadius, 15)
        XCTAssertEqual(s.borderWidth, 1)
    }

    func testScreenSpaceFlipsY() {
        let r = CGRect(x: 10, y: 20, width: 300, height: 100)
        let c = ScreenSpace.cocoa(r, primaryHeight: 1000)
        XCTAssertEqual(c, CGRect(x: 10, y: 880, width: 300, height: 100))
        XCTAssertEqual(ScreenSpace.cocoa(c, primaryHeight: 1000), r)
    }

    func testPixelAlignedScale2RoundsToHalf() {
        let out = ScreenSpace.pixelAligned(CGRect(x: 10.3, y: 20.7, width: 100.2, height: 50.1), scale: 2)
        XCTAssertEqual(out.minX, 10.5)
        XCTAssertEqual(out.minY, 20.5)
        XCTAssertEqual(out.maxX, 110.5)
        XCTAssertEqual(out.maxY, 71)
        XCTAssertEqual(ScreenSpace.pixelAligned(CGRect(x: 1, y: 2, width: 3, height: 4), scale: 2), CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    func testIsBlack() throws {
        func image(_ r: UInt8, _ g: UInt8, _ b: UInt8) throws -> CGImage {
            let ctx = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.setFillColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            return try XCTUnwrap(ctx.makeImage())
        }
        XCTAssertTrue(WorkspaceSlide.isBlack(try image(0, 0, 0)))
        XCTAssertFalse(WorkspaceSlide.isBlack(try image(0x18, 0x19, 0x20)))
    }

    func testWorkspaceTransitionEquatable() {
        let region = CGRect(x: 0, y: 25, width: 1000, height: 700)
        let t = WorkspaceTransition(displayID: 1, region: region, kind: .horizontal(forward: true))
        XCTAssertEqual(t, WorkspaceTransition(displayID: 1, region: region, kind: .horizontal(forward: true)))
        XCTAssertNotEqual(t, WorkspaceTransition(displayID: 1, region: region, kind: .horizontal(forward: false)))
        XCTAssertNotEqual(t, WorkspaceTransition(displayID: 2, region: region, kind: .specialIn))
    }
}
