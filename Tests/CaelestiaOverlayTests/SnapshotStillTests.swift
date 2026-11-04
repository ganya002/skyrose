import AppKit
import CaelestiaCore
import XCTest

@testable import CaelestiaOverlay

/// Stills of the snapshot animation: when a still fits a window, its colour statistics, and how a
/// cover draws them (1:1, never stretched to the tile).
@MainActor
final class SnapshotStillTests: XCTestCase {
    // MARK: Helpers

    func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, alpha: UInt8 = 255, size: Int = 64) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let a = Double(alpha) / 255
        ctx.setFillColor(red: Double(r) / 255 * a, green: Double(g) / 255 * a, blue: Double(b) / 255 * a, alpha: a)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return try XCTUnwrap(ctx.makeImage())
    }

    /// A clear image with one opaque rect (bitmap coordinates, y up).
    func block(_ rect: CGRect, in size: Int = 128) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        ctx.fill(rect)
        return try XCTUnwrap(ctx.makeImage())
    }

    func still(_ size: CGSize, contentRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), fill: CGColor? = nil,
               color: (UInt8, UInt8, UInt8) = (10, 20, 30)) throws -> SnapshotCache.Still {
        SnapshotCache.Still(image: try solid(color.0, color.1, color.2), size: size, capturedAt: 0, contentRect: contentRect, fill: fill)
    }

    // MARK: Still

    func testFitsWithinOneAndAHalfPoints() throws {
        let s = try still(CGSize(width: 800, height: 600))
        XCTAssertTrue(s.fits(CGSize(width: 800, height: 600)))
        XCTAssertTrue(s.fits(CGSize(width: 801.5, height: 598.5)), "±1.5 inclusive")
        XCTAssertTrue(s.fits(CGSize(width: 798.5, height: 601.5)))
        XCTAssertFalse(s.fits(CGSize(width: 801.6, height: 600)))
        XCTAssertFalse(s.fits(CGSize(width: 800, height: 598.4)))
        XCTAssertFalse(s.fits(CGSize(width: 400, height: 600)))
    }

    func testContentRectBelowNinetySevenPercentDoesNotFit() throws {
        let size = CGSize(width: 800, height: 600)
        XCTAssertTrue(try still(size, contentRect: CGRect(x: 0, y: 0, width: 0.97, height: 0.97)).fits(size))
        XCTAssertTrue(try still(size, contentRect: CGRect(x: 0.01, y: 0.01, width: 0.98, height: 0.98)).fits(size))
        XCTAssertFalse(try still(size, contentRect: CGRect(x: 0, y: 0, width: 0.969, height: 1)).fits(size), "transparent margin on the right")
        XCTAssertFalse(try still(size, contentRect: CGRect(x: 0, y: 0, width: 1, height: 0.5)).fits(size), "stale smaller buffer")
    }

    func testContentSizeScalesByTheContentRect() throws {
        XCTAssertEqual(try still(CGSize(width: 400, height: 300)).contentSize, CGSize(width: 400, height: 300))
        let part = try still(CGSize(width: 400, height: 300), contentRect: CGRect(x: 0, y: 0, width: 0.5, height: 0.25))
        XCTAssertEqual(part.contentSize, CGSize(width: 200, height: 75))
    }

    // MARK: Colour statistics

    func testAverageColorOfASolidImage() throws {
        let c = try XCTUnwrap(SnapshotCache.averageColor(try solid(200, 100, 50)))
        let comps = try XCTUnwrap(c.components)
        XCTAssertEqual(comps[0], 200.0 / 255, accuracy: 0.02)
        XCTAssertEqual(comps[1], 100.0 / 255, accuracy: 0.02)
        XCTAssertEqual(comps[2], 50.0 / 255, accuracy: 0.02)
        XCTAssertEqual(c.alpha, 1)
    }

    func testAverageColorIgnoresClearPixelsAndIsNilForAClearImage() throws {
        // Left half blue, right half clear: the average is the blue alone.
        let half = try block(CGRect(x: 0, y: 0, width: 64, height: 128))
        let comps = try XCTUnwrap(SnapshotCache.averageColor(half)?.components)
        XCTAssertEqual(comps[0], 0, accuracy: 0.02)
        XCTAssertEqual(comps[2], 1, accuracy: 0.02)
        XCTAssertNil(SnapshotCache.averageColor(try solid(255, 255, 255, alpha: 0)))
    }

    func testOpaqueBoundsOfAFullAndOfAClearImageIsTheUnitRect() throws {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        XCTAssertEqual(SnapshotCache.opaqueBounds(try solid(1, 2, 3)), unit)
        XCTAssertEqual(SnapshotCache.opaqueBounds(try solid(1, 2, 3, alpha: 0)), unit)
    }

    func testOpaqueBoundsOfACornerBlockIsYDown() throws {
        // 64×64 opaque block in the bottom-left of the bitmap (y up) = the lower-left in y-down terms.
        let r = SnapshotCache.opaqueBounds(try block(CGRect(x: 0, y: 0, width: 64, height: 64)))
        XCTAssertEqual(r.minX, 0, accuracy: 0.03)
        XCTAssertEqual(r.minY, 0.5, accuracy: 0.03)
        XCTAssertEqual(r.width, 0.5, accuracy: 0.03)
        XCTAssertEqual(r.height, 0.5, accuracy: 0.03)
        // Within two cells of the full image: rounded window corners do not count.
        let almost = SnapshotCache.opaqueBounds(try block(CGRect(x: 1, y: 1, width: 126, height: 126)))
        XCTAssertEqual(almost, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testMakeStillCombinesBoundsAndColour() throws {
        let s = SnapshotCache.makeStill(try block(CGRect(x: 0, y: 0, width: 64, height: 128)), size: CGSize(width: 300, height: 200))
        XCTAssertEqual(s.size, CGSize(width: 300, height: 200))
        XCTAssertEqual(s.contentRect.width, 0.5, accuracy: 0.03)
        XCTAssertEqual(s.contentRect.height, 1, accuracy: 0.03)
        XCTAssertNotNil(s.fill)
        XCTAssertFalse(s.fits(CGSize(width: 300, height: 200)), "half the width is transparent")
    }

    // MARK: SnapshotCover

    let region = CGRect(x: 0, y: 0, width: 800, height: 600)
    let style = OverlayStyle.gabby

    func cover() -> SnapshotCover {
        SnapshotCover(displayID: 1, region: region, desktop: nil, style: style)
    }

    /// Regression (live finding): the cover drew in the view's backing layer, whose
    /// `isGeometryFlipped` AppKit owns, so stacked windows swapped places while it was up.
    func testCoverDrawsInItsOwnFlippedRootSoTopLeftFramesStayOnTop() {
        let c = cover()
        XCTAssertTrue(c.root.isGeometryFlipped)
        XCTAssertFalse(c.root === c.window.contentView?.layer, "the root must be our own sublayer")
        XCTAssertTrue(c.root.superlayer === c.window.contentView?.layer)
        c.render([sample(1, frame: CGRect(x: 0, y: 0, width: 800, height: 290)),
                  sample(2, frame: CGRect(x: 0, y: 310, width: 800, height: 290))], image: { _ in nil }, style: style)
        // In a flipped root, a smaller y is nearer the top of the screen.
        let top = try! XCTUnwrap(c.tiles[1]?.container.frame), bottom = try! XCTUnwrap(c.tiles[2]?.container.frame)
        XCTAssertLessThan(top.midY, bottom.midY)
        c.close()
    }

    func sample(_ id: CGWindowID = 7, frame: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300), alpha: Double = 1,
                decorated: Bool = true) -> WindowMotionSample {
        WindowMotionSample(id: id, displayID: 1, frame: frame, alpha: alpha, scale: 1, isActive: true, decorated: decorated, isDragged: false)
    }

    func testStillIsDrawnOneToOneNotStretchedToTheTile() throws {
        let c = cover()
        defer { c.close() }
        let fill = CGColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let s = try still(CGSize(width: 300, height: 200), fill: fill)
        c.render([sample()], image: { _ in s }, style: style)
        let tile = try XCTUnwrap(c.tiles[7])
        let bw = style.borderWidth
        XCTAssertEqual(tile.container.bounds.size, CGSize(width: 400 + 2 * bw, height: 300 + 2 * bw))
        XCTAssertEqual(tile.image.frame, CGRect(x: 0, y: 0, width: 300, height: 200), "the still's own size, top-left")
        XCTAssertNotEqual(tile.image.frame.size, tile.clip.frame.size)
        XCTAssertEqual(tile.clip.frame, CGRect(x: bw, y: bw, width: 400, height: 300), "the tile's inner rect")
        XCTAssertEqual(tile.clip.backgroundColor, fill, "the fill shows where the still does not reach")
        XCTAssertEqual(tile.clip.cornerRadius, style.cornerRadius)
        XCTAssertEqual(tile.container.opacity, 1)
        XCTAssertTrue(tile.clip.masksToBounds)
    }

    func testStillWithoutFillUsesTheSurfaceColour() throws {
        let c = cover()
        defer { c.close() }
        c.render([sample()], image: { _ in try? self.still(CGSize(width: 100, height: 100)) }, style: style)
        XCTAssertEqual(c.tiles[7]?.clip.backgroundColor, style.surface.cgColor)
    }

    func testContentRectShrinksTheDrawnSize() throws {
        let c = cover()
        defer { c.close() }
        let s = try still(CGSize(width: 400, height: 300), contentRect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        c.render([sample()], image: { _ in s }, style: style)
        let tile = try XCTUnwrap(c.tiles[7])
        XCTAssertEqual(tile.image.frame.size, CGSize(width: 200, height: 150))
        XCTAssertEqual(tile.image.contentsRect, s.contentRect)
    }

    func testTileFollowsALargerOrSmallerFrameWithoutRescalingTheStill() throws {
        let c = cover()
        defer { c.close() }
        let s = try still(CGSize(width: 300, height: 200))
        for f in [CGRect(x: 0, y: 0, width: 600, height: 500), CGRect(x: 50, y: 50, width: 150, height: 100)] {
            c.render([sample(frame: f)], image: { _ in s }, style: style)
            let tile = try XCTUnwrap(c.tiles[7])
            XCTAssertEqual(tile.image.frame.size, CGSize(width: 300, height: 200))
            XCTAssertEqual(tile.clip.frame.size, f.size, "clip is the tile, the still is cut off or padded by the fill")
        }
    }

    func testTileWithoutAStillStaysInvisible() {
        let c = cover()
        defer { c.close() }
        c.render([sample()], image: { _ in nil }, style: style)
        XCTAssertEqual(c.tiles[7]?.container.opacity, 0)
        XCTAssertEqual(c.tiles[7]?.hasImage, false)
    }

    func testUndecoratedWindowHasNoRing() throws {
        let c = cover()
        defer { c.close() }
        let s = try still(CGSize(width: 400, height: 300))
        c.render([sample(decorated: false)], image: { _ in s }, style: style)
        let tile = try XCTUnwrap(c.tiles[7])
        XCTAssertTrue(tile.ring.isHidden)
        XCTAssertEqual(tile.clip.frame.size, CGSize(width: 400, height: 300))
    }

    func testFreshStillSetsOpacityFromProgressClamped() throws {
        let c = cover()
        defer { c.close() }
        let s = try still(CGSize(width: 300, height: 200))
        let fresh = try still(CGSize(width: 400, height: 300), color: (200, 0, 0))
        var progress = 0.4
        for (p, expected) in [(0.4, Float(0.4)), (1.7, Float(1)), (-0.2, Float(0)), (0.0, Float(0))] {
            progress = p
            c.render([sample()], image: { _ in s }, fresh: { _ in (fresh, progress) }, style: style)
            XCTAssertEqual(try XCTUnwrap(c.tiles[7]).fresh.opacity, expected, accuracy: 1e-6)
        }
        let tile = try XCTUnwrap(c.tiles[7])
        XCTAssertTrue(tile.hasFresh)
        XCTAssertEqual(tile.fresh.frame.size, CGSize(width: 400, height: 300), "the fresh capture is 1:1 too")
        XCTAssertEqual(tile.image.frame.size, CGSize(width: 300, height: 200))
    }

    func testNoFreshStillLeavesItTransparent() throws {
        let c = cover()
        defer { c.close() }
        let s = try still(CGSize(width: 300, height: 200))
        c.render([sample()], image: { _ in s }, style: style)
        XCTAssertEqual(c.tiles[7]?.fresh.opacity, 0)
        XCTAssertEqual(c.tiles[7]?.hasFresh, false)
    }

    func testTilesOfGoneWindowsAreRemovedAndOtherDisplaysIgnored() throws {
        let c = cover()
        defer { c.close() }
        let s = try still(CGSize(width: 100, height: 100))
        var other = sample(9)
        other.displayID = 2
        c.render([sample(7), sample(8), other], image: { _ in s }, style: style)
        XCTAssertEqual(Set(c.tiles.keys), [7, 8])
        c.render([sample(8)], image: { _ in s }, style: style)
        XCTAssertEqual(Set(c.tiles.keys), [8])
    }

    func testHolesMaskTheBackgroundAndResetClearsThem() throws {
        let c = cover()
        defer { c.close() }
        let s = try still(CGSize(width: 100, height: 100))
        XCTAssertNil(c.background.mask)
        XCTAssertNotNil(c.root.backgroundColor)
        c.render([sample()], image: { _ in s }, holes: [CGRect(x: 50, y: 50, width: 100, height: 100)], style: style)
        let mask = try XCTUnwrap(c.background.mask as? CAShapeLayer)
        XCTAssertEqual(mask.fillRule, .evenOdd)
        XCTAssertNil(c.root.backgroundColor, "the root fill would cover the hole")
        let box = try XCTUnwrap(mask.path).boundingBoxOfPath
        XCTAssertEqual(box, c.background.bounds)
        XCTAssertFalse(try XCTUnwrap(mask.path).contains(CGPoint(x: 100, y: 100), using: .evenOdd), "inside the hole")
        XCTAssertTrue(try XCTUnwrap(mask.path).contains(CGPoint(x: 400, y: 400), using: .evenOdd))

        // No holes any more: the mask goes and the fill returns.
        c.render([sample()], image: { _ in s }, holes: [], style: style)
        XCTAssertNil(c.background.mask)
        XCTAssertNotNil(c.root.backgroundColor)

        c.render([sample()], image: { _ in s }, holes: [CGRect(x: 50, y: 50, width: 100, height: 100)], style: style)
        XCTAssertNotNil(c.background.mask)
        c.reset()
        XCTAssertNil(c.background.mask)
        XCTAssertNotNil(c.root.backgroundColor)
        XCTAssertTrue(c.tiles.isEmpty)
    }

    func testHolesOutsideTheDisplayAreIgnored() throws {
        let c = cover()
        defer { c.close() }
        c.render([], image: { _ in nil }, holes: [CGRect(x: 5000, y: 5000, width: 10, height: 10)], style: style)
        XCTAssertNil(c.background.mask)
    }

    func testHoleIsRelativeToTheDisplayRegion() throws {
        let second = SnapshotCover(displayID: 2, region: CGRect(x: 800, y: 0, width: 800, height: 600), desktop: nil, style: style)
        defer { second.close() }
        second.render([], image: { _ in nil }, holes: [CGRect(x: 900, y: 100, width: 50, height: 50)], style: style)
        let mask = try XCTUnwrap(second.background.mask as? CAShapeLayer)
        XCTAssertFalse(try XCTUnwrap(mask.path).contains(CGPoint(x: 125, y: 125), using: .evenOdd))
        XCTAssertTrue(try XCTUnwrap(mask.path).contains(CGPoint(x: 600, y: 400), using: .evenOdd))
    }
}
