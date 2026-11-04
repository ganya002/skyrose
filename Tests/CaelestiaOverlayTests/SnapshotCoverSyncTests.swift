import AppKit
import CaelestiaCore
import QuartzCore
import XCTest

@testable import CaelestiaOverlay

/// `SnapshotCover.sync`: the motion model's channel segments become Core Animation animations the
/// render server plays by itself, while the layers' model values are already the final frame.
@MainActor
final class SnapshotCoverSyncTests: XCTestCase {
    let displayID: CGDirectDisplayID = 1
    let region = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let displays: [CGDirectDisplayID: CGRect] = [1: CGRect(x: 0, y: 0, width: 1000, height: 800)]
    let style = OverlayStyle.gabby
    let a = CGRect(x: 0, y: 0, width: 400, height: 300)
    let b = CGRect(x: 500, y: 100, width: 300, height: 400)
    let c = CGRect(x: 100, y: 400, width: 200, height: 200)

    private func request(_ changes: [WindowFrameChange], _ frame: CGRect) -> WindowAnimationRequest {
        WindowAnimationRequest(changes: changes, windows: [AnimatedWindow(id: 1, frame: frame, displayID: displayID, isActive: false)], displays: displays)
    }

    private func still() throws -> SnapshotCache.Still {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return SnapshotCache.Still(image: try XCTUnwrap(ctx.makeImage()), size: CGSize(width: 400, height: 300), capturedAt: 0,
                                   contentRect: CGRect(x: 0, y: 0, width: 1, height: 1), fill: nil)
    }

    private func sync(_ cover: SnapshotCover, _ m: WindowMotionModel, at now: TimeInterval) throws {
        let still = try still()
        cover.sync(m.order.compactMap { m.items[$0] }, now: now, image: { _ in still }, style: style)
    }

    /// A model with window 1 settled at `a`, then moved to `b` at `t0`.
    private func movedModel(at t0: TimeInterval) -> WindowMotionModel {
        var m = WindowMotionModel()
        m.apply(request([], a), at: t0 - 100)
        m.apply(request([WindowFrameChange(id: 1, kind: .move, from: a, to: b)], b), at: t0)
        return m
    }

    func testAMoveBecomesSpringAnimationsStartingAtTheModelStart() throws {
        let t0 = CACurrentMediaTime()
        let m = movedModel(at: t0)
        let cover = SnapshotCover(displayID: displayID, region: region, desktop: nil, style: style)
        defer { cover.close() }
        try sync(cover, m, at: t0)
        let tile = try XCTUnwrap(cover.tiles[1])

        let keys = Set(tile.container.animationKeys() ?? [])
        for key in ["x.position.x", "y.position.y", "w.position.x", "h.position.y", "w.bounds.size.width", "h.bounds.size.height"] {
            XCTAssertTrue(keys.contains(key), "\(key) missing from \(keys)")
        }
        XCTAssertNotNil(tile.clip.animation(forKey: "w.bounds.size.width"))
        XCTAssertNotNil(tile.ring.animation(forKey: "h.bounds.size.height"))

        let x = try XCTUnwrap(tile.container.animation(forKey: "x.position.x") as? CASpringAnimation)
        XCTAssertEqual(x.mass, Spring.snappy.mass)
        XCTAssertEqual(x.stiffness, Spring.snappy.stiffness)
        XCTAssertEqual(x.damping, Spring.snappy.damping)
        XCTAssertEqual(x.beginTime, tile.container.convertTime(t0, from: nil), accuracy: 1e-6)
        XCTAssertEqual(x.beginTime, t0, accuracy: 1e-3, "on the media clock the model uses")
        XCTAssertTrue(x.isAdditive, "position parts are offsets from the final value")
        XCTAssertEqual(try XCTUnwrap(x.fromValue as? Double), a.minX - b.minX, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(x.toValue as? Double), 0, accuracy: 1e-9)

        let w = try XCTUnwrap(tile.container.animation(forKey: "w.bounds.size.width") as? CASpringAnimation)
        XCTAssertFalse(w.isAdditive)
        XCTAssertEqual(w.beginTime, x.beginTime, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(w.fromValue as? Double), a.width + 2 * style.borderWidth, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(w.toValue as? Double), b.width + 2 * style.borderWidth, accuracy: 1e-6)
    }

    func testTheLayerModelValuesAreTheFinalFrame() throws {
        let t0 = CACurrentMediaTime()
        let m = movedModel(at: t0)
        let cover = SnapshotCover(displayID: displayID, region: region, desktop: nil, style: style)
        defer { cover.close() }
        try sync(cover, m, at: t0)
        let tile = try XCTUnwrap(cover.tiles[1])
        let bw = style.borderWidth
        XCTAssertEqual(tile.container.position.x, b.midX, accuracy: 1e-6)
        XCTAssertEqual(tile.container.position.y, b.midY, accuracy: 1e-6)
        XCTAssertEqual(tile.container.bounds.width, b.width + 2 * bw, accuracy: 1e-6)
        XCTAssertEqual(tile.container.bounds.height, b.height + 2 * bw, accuracy: 1e-6)
        XCTAssertEqual(tile.clip.bounds.width, b.width, accuracy: 1e-6)
        XCTAssertEqual(tile.clip.bounds.height, b.height, accuracy: 1e-6)
        XCTAssertEqual(tile.ring.bounds.size, tile.container.bounds.size)
        XCTAssertEqual(tile.container.opacity, 1)
    }

    func testResyncingWithoutChangeKeepsTheAnimationObjects() throws {
        let t0 = CACurrentMediaTime()
        let m = movedModel(at: t0)
        let cover = SnapshotCover(displayID: displayID, region: region, desktop: nil, style: style)
        defer { cover.close() }
        try sync(cover, m, at: t0)
        let tile = try XCTUnwrap(cover.tiles[1])
        let keys = (tile.container.animationKeys() ?? []).sorted()
        let before = try keys.map { try XCTUnwrap(tile.container.animation(forKey: $0)) }

        try sync(cover, m, at: t0 + 0.05)
        try sync(cover, m, at: t0 + 0.10)
        XCTAssertEqual((tile.container.animationKeys() ?? []).sorted(), keys)
        for (key, old) in zip(keys, before) {
            let now = try XCTUnwrap(tile.container.animation(forKey: key))
            XCTAssertTrue(now === old, "\(key) was replaced by a no-change sync")
        }
    }

    func testARetargetReplacesTheAnimationStartingFromTheCurrentValue() throws {
        let t0 = CACurrentMediaTime()
        var m = movedModel(at: t0)
        let cover = SnapshotCover(displayID: displayID, region: region, desktop: nil, style: style)
        defer { cover.close() }
        try sync(cover, m, at: t0)
        let tile = try XCTUnwrap(cover.tiles[1])
        let first = try XCTUnwrap(tile.container.animation(forKey: "w.bounds.size.width") as? CASpringAnimation)
        let firstX = try XCTUnwrap(tile.container.animation(forKey: "x.position.x") as? CASpringAnimation)

        let t1 = t0 + 0.06
        let currentW = m.items[1]!.w.value(at: t1)
        let currentX = m.items[1]!.x.value(at: t1)
        XCTAssertNotEqual(currentW, a.width, accuracy: 1, "mid-flight")
        m.apply(request([WindowFrameChange(id: 1, kind: .move, from: nil, to: c)], c), at: t1)
        try sync(cover, m, at: t1)

        let second = try XCTUnwrap(tile.container.animation(forKey: "w.bounds.size.width") as? CASpringAnimation)
        XCTAssertFalse(second === first)
        XCTAssertEqual(try XCTUnwrap(second.fromValue as? Double), currentW + 2 * style.borderWidth, accuracy: 1e-6, "starts where the tile is now")
        XCTAssertEqual(try XCTUnwrap(second.toValue as? Double), c.width + 2 * style.borderWidth, accuracy: 1e-6)
        XCTAssertEqual(second.beginTime, t1, accuracy: 1e-3)
        XCTAssertNotEqual(second.initialVelocity, 0, "the spring keeps the velocity it had")

        let secondX = try XCTUnwrap(tile.container.animation(forKey: "x.position.x") as? CASpringAnimation)
        XCTAssertFalse(secondX === firstX)
        XCTAssertEqual(try XCTUnwrap(secondX.fromValue as? Double), currentX - c.minX, accuracy: 1e-6)

        // The model values moved on to the new target.
        XCTAssertEqual(tile.container.position.x, c.midX, accuracy: 1e-6)
        XCTAssertEqual(tile.clip.bounds.width, c.width, accuracy: 1e-6)
    }

    func testASnapRemovesTheRunningAnimations() throws {
        let t0 = CACurrentMediaTime()
        var m = movedModel(at: t0)
        let cover = SnapshotCover(displayID: displayID, region: region, desktop: nil, style: style)
        defer { cover.close() }
        try sync(cover, m, at: t0)
        let tile = try XCTUnwrap(cover.tiles[1])
        XCTAssertFalse((tile.container.animationKeys() ?? []).isEmpty)
        // Motion switched off (or Reduce Motion): the next retarget snaps, nothing is left to play.
        m.table[.windowsMove] = .disabled
        m.apply(request([WindowFrameChange(id: 1, kind: .move, from: nil, to: c)], c), at: t0 + 0.05)
        try sync(cover, m, at: t0 + 0.05)
        XCTAssertTrue((tile.container.animationKeys() ?? []).isEmpty, "\(tile.container.animationKeys() ?? [])")
        XCTAssertEqual(tile.container.position.x, c.midX, accuracy: 1e-6)
    }
}
