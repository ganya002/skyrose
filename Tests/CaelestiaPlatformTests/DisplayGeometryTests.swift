import XCTest
import CoreGraphics
import CaelestiaCore
@testable import CaelestiaPlatform

/// Coordinate converter and usable-area math for multi-display layouts, negative origins and the
/// notch (spec 4.6, 12.1). AppKit rects in, top-left rects out.
final class DisplayGeometryTests: XCTestCase {
    typealias Facts = DisplayGeometry.ScreenFacts

    /// 13" Air: 1470×956, notch, menu bar 33 pt, Dock hidden (4 pt sliver).
    let air = Facts(
        uuid: "air", frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        visibleFrame: CGRect(x: 0, y: 4, width: 1470, height: 919), safeAreaTop: 32, scale: 2
    )

    func external(at origin: CGPoint, size: CGSize = CGSize(width: 2560, height: 1440)) -> Facts {
        Facts(uuid: "ext", frame: CGRect(origin: origin, size: size), visibleFrame: CGRect(origin: origin, size: size))
    }

    func testNotchFromTheSafeAreaOrAuxiliaryGapFeedsTheCornerDefault() {
        XCTAssertTrue(DisplayGeometry.panelHasNotch(
            safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 0, width: 10, height: 32),
            auxiliaryTopRight: CGRect(x: 200, y: 0, width: 10, height: 32)))
        XCTAssertTrue(DisplayGeometry.panelHasNotch(
            safeAreaTop: 0,
            auxiliaryTopLeft: CGRect(x: 0, y: 0, width: 100, height: 20),
            auxiliaryTopRight: CGRect(x: 180, y: 0, width: 100, height: 20)))
        XCTAssertFalse(DisplayGeometry.panelHasNotch(safeAreaTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil))

        var built = air
        built.isBuiltIn = true
        built.auxiliaryTopLeft = CGRect(x: 0, y: 924, width: 600, height: 32)
        built.auxiliaryTopRight = CGRect(x: 800, y: 924, width: 670, height: 32)
        let notch = DisplayGeometry.info(for: built, converter: CoordinateConverter(primaryHeight: 956))
        XCTAssertTrue(notch.hasNotch)
        XCTAssertTrue(notch.isBuiltIn)
        XCTAssertEqual(notch.id, "air", "the radius is stored by display UUID, not by screen index")
        let frame = FrameConfig()
        XCTAssertEqual(frame.cornerRadius(isBuiltIn: notch.isBuiltIn, hasNotch: notch.hasNotch), FrameConfig.autoBuiltInRadius)
        XCTAssertEqual(frame.bottomCornerRadius(isBuiltIn: notch.isBuiltIn, hasNotch: notch.hasNotch), 0)

        let ext = DisplayGeometry.info(for: external(at: .zero), converter: CoordinateConverter(primaryHeight: 1440))
        XCTAssertFalse(ext.isBuiltIn)
        XCTAssertFalse(ext.hasNotch)
        XCTAssertEqual(frame.cornerRadius(isBuiltIn: ext.isBuiltIn, hasNotch: ext.hasNotch), 0)
        XCTAssertEqual(frame.bottomCornerRadius(isBuiltIn: ext.isBuiltIn, hasNotch: ext.hasNotch), 0)
    }

    func testPrimaryOnly() {
        let d = DisplayGeometry.displays(from: [air])[0]
        XCTAssertEqual(d.frame, CGRect(x: 0, y: 0, width: 1470, height: 956))
        XCTAssertEqual(d.menuBarHeight, 33)
        XCTAssertEqual(d.dockInsets, .zero, "auto-hide sliver is ignored")
        XCTAssertTrue(d.isPrimary)
        XCTAssertEqual(d.usableArea(reserved: .uniform(10)), CGRect(x: 10, y: 43, width: 1450, height: 903))
    }

    func testNotchStaysReservedWhenMenuBarIsHidden() {
        var hidden = air
        hidden.visibleFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)
        XCTAssertEqual(DisplayGeometry.displays(from: [hidden])[0].menuBarHeight, 32)
        hidden.safeAreaTop = 0
        XCTAssertEqual(DisplayGeometry.displays(from: [hidden])[0].menuBarHeight, 0, "no notch, hidden menu bar")
    }

    func testVisibleDockOnEachEdge() {
        var bottom = air
        bottom.visibleFrame = CGRect(x: 0, y: 70, width: 1470, height: 853)
        XCTAssertEqual(DisplayGeometry.displays(from: [bottom])[0].dockInsets, Insets(bottom: 70))
        var left = air
        left.visibleFrame = CGRect(x: 64, y: 0, width: 1406, height: 923)
        XCTAssertEqual(DisplayGeometry.displays(from: [left])[0].dockInsets, Insets(left: 64))
        var right = air
        right.visibleFrame = CGRect(x: 0, y: 0, width: 1406, height: 923)
        XCTAssertEqual(DisplayGeometry.displays(from: [right])[0].dockInsets, Insets(right: 64))
    }

    func testExternalToTheRightTopAligned() {
        // AppKit: external top edge aligned with the Air's top → its origin.y = 956 − 1440.
        let ds = DisplayGeometry.displays(from: [air, external(at: CGPoint(x: 1470, y: -484))])
        XCTAssertEqual(ds[1].frame, CGRect(x: 1470, y: 0, width: 2560, height: 1440))
        XCTAssertFalse(ds[1].isPrimary)
    }

    func testExternalToTheLeftHasNegativeX() {
        let ds = DisplayGeometry.displays(from: [air, external(at: CGPoint(x: -2560, y: 0))])
        // Bottom-aligned in AppKit: top-left y = 956 − 1440 = −484.
        XCTAssertEqual(ds[1].frame, CGRect(x: -2560, y: -484, width: 2560, height: 1440))
    }

    func testExternalAboveHasNegativeY() {
        let ds = DisplayGeometry.displays(from: [air, external(at: CGPoint(x: 0, y: 956))])
        XCTAssertEqual(ds[1].frame, CGRect(x: 0, y: -1440, width: 2560, height: 1440))
    }

    func testExternalBelow() {
        let ds = DisplayGeometry.displays(from: [air, external(at: CGPoint(x: 0, y: -1440))])
        XCTAssertEqual(ds[1].frame, CGRect(x: 0, y: 956, width: 2560, height: 1440))
    }

    func testPrimaryIsFoundEvenWhenNotFirst() {
        let ds = DisplayGeometry.displays(from: [external(at: CGPoint(x: 1470, y: 0)), air])
        XCTAssertEqual(ds[0].frame.minY, 956 - 1440)
        XCTAssertTrue(ds[1].isPrimary)
    }

    func testConverterRoundTrips() {
        let c = CoordinateConverter(primaryHeight: 956)
        for r in [CGRect(x: -2560, y: -300, width: 800, height: 600), CGRect(x: 100, y: 1200, width: 50, height: 70)] {
            XCTAssertEqual(c.toBottomLeft(c.toTopLeft(r)), r)
        }
        XCTAssertEqual(c.toTopLeft(CGPoint(x: 5, y: 956)), CGPoint(x: 5, y: 0))
    }

    func testReservedInsetsAddPersistentBar() {
        XCTAssertEqual(DisplayGeometry.reservedInsets(screenFrame: 10, persistentBarWidth: nil), .uniform(10))
        XCTAssertEqual(DisplayGeometry.reservedInsets(screenFrame: 10, persistentBarWidth: 48), Insets(top: 10, left: 48, bottom: 10, right: 10))
    }

    func testDisplayLookupAndNeighbours() {
        let ds = DisplayGeometry.displays(from: [air, external(at: CGPoint(x: 1470, y: -484))])
        XCTAssertEqual(DisplayGeometry.display(containing: CGPoint(x: 2000, y: 100), in: ds)?.id, "ext")
        XCTAssertEqual(DisplayGeometry.display(containing: CGPoint(x: -50, y: 100), in: ds)?.id, "air", "nearest")
        XCTAssertEqual(DisplayGeometry.display(for: CGRect(x: 1400, y: 100, width: 400, height: 300), in: ds)?.id, "ext")
        XCTAssertEqual(DisplayGeometry.neighbor(of: ds[0], direction: .right, in: ds)?.id, "ext")
        XCTAssertEqual(DisplayGeometry.neighbor(of: ds[1], direction: .left, in: ds)?.id, "air")
        XCTAssertNil(DisplayGeometry.neighbor(of: ds[0], direction: .left, in: ds))
    }
}
