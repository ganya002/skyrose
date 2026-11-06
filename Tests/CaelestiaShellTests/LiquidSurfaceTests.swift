import AppKit
@testable import CaelestiaCore
@testable import CaelestiaShell
import XCTest

@MainActor
final class LiquidSurfaceTests: XCTestCase {
    func scene() -> BlobScene {
        let b = CGRect(x: 0, y: 0, width: 400, height: 300)
        let frame = BlobFrame(outer: b.insetBy(dx: -50, dy: -50), inner: b.insetBy(dx: 10, dy: 10), radius: 25)
        let launcher = BlobRect(rect: CGRect(x: 120, y: 190, width: 160, height: 100), radii: .uniform(28))
        let osd = BlobRect(rect: CGRect(x: 340, y: 90, width: 50, height: 120), radii: .uniform(28),
                           deform: BlobDeform(m00: 1.2, m01: 0.05, m11: 1 / 1.2))
        return BlobScene(rects: [launcher, osd], frame: frame)
    }

    /// The Metal shader and the CPU port agree on what is inside the surface.
    func testShaderMatchesTheCPUPort() throws {
        guard LiquidSurface.isSupported else { throw XCTSkip("no Metal") }
        let s = scene()
        let size = CGSize(width: 400, height: 300)
        let surface = LiquidSurface(frame: CGRect(origin: .zero, size: size))
        let bytes = try XCTUnwrap(surface.renderOffscreen(s, size: size))
        let radii = BlobSDF.effectiveRadii(s)
        var checked = 0, wrong: [String] = []
        for y in stride(from: 2, to: 300, by: 7) {
            for x in stride(from: 2, to: 400, by: 7) {
                let p = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                let d = BlobSDF.distance(at: p, scene: s, radii: radii)
                guard abs(d) > 1.5 else { continue }
                let a = bytes[(y * 400 + x) * 4 + 3]
                checked += 1
                if (d < 0) != (a > 127) { wrong.append("(\(x),\(y)) d=\(d) a=\(a)") }
            }
        }
        XCTAssertGreaterThan(checked, 1500)
        XCTAssertTrue(wrong.isEmpty, wrong.prefix(10).joined(separator: "; "))
    }

    /// Part 7a regression (launcher black flash): while a drawer slides and squashes, nothing may
    /// be drawn outside the blob and its soft shadow. The shader culls each rect outside a box at
    /// half + 1.5 k; `fwidth` across that 1e10 jump used to turn the box edge into a 1–2 px line of
    /// half-opaque fill (dark outline + rectangle above the launcher) whenever the box landed on an
    /// odd pixel, i.e. on most frames of the open / close animation.
    func testNothingIsDrawnOutsideTheBlobWhileADrawerAnimates() throws {
        guard LiquidSurface.isSupported else { throw XCTSkip("no Metal") }
        let w = 900, h = 700
        let size = CGSize(width: w, height: h)
        let surface = LiquidSurface(frame: CGRect(origin: .zero, size: size))
        let b = CGRect(origin: .zero, size: size)
        let frame = BlobFrame(outer: b.insetBy(dx: -50, dy: -50), inner: b.insetBy(dx: 10, dy: 10), radius: 25)
        let rest = CGRect(x: 135, y: 147, width: 630, height: 543)
        let reach = surface.shadowBlur + 3
        var bad: [String] = []
        // Offsets and squashes like the open / close animation, at odd and fractional positions.
        let steps: [(Double, BlobDeform)] = [
            (0.93, BlobDeform(m00: 1.0, m01: 0, m11: 1.0)),
            (0.71, BlobDeform(m00: 0.93, m01: 0, m11: 1.08)),
            (0.437, BlobDeform(m00: 0.88, m01: 0.01, m11: 1.14)),
            (0.2113, BlobDeform(m00: 1.05, m01: 0, m11: 0.95)),
            (0.0571, BlobDeform(m00: 1.01, m01: 0, m11: 0.99)),
        ]
        for (step, (offset, deform)) in steps.enumerated() {
            for dx in [0.5, 1.37] {
                let r = surface.slid(rest, edge: .bottom, offset: offset).offsetBy(dx: dx, dy: 0)
                let scene = BlobScene(rects: [BlobRect(rect: r, radii: .uniform(28), deform: deform)], frame: frame)
                let radii = BlobSDF.effectiveRadii(scene)
                for mask in [false, true] {
                    let bytes = try XCTUnwrap(surface.renderOffscreen(scene, size: size, mask: mask))
                    for y in stride(from: 12, to: h - 12, by: 1) {
                        for x in stride(from: 12, to: w - 12, by: 1) {
                            let a = bytes[(y * w + x) * 4 + 3]
                            guard a > 2 else { continue }
                            let d = BlobSDF.distance(at: CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5), scene: scene, radii: radii)
                            if d > reach, bad.count < 12 { bad.append("step \(step) dx \(dx) mask \(mask) (\(x),\(y)) a=\(a) d=\(Int(d))") }
                        }
                    }
                }
            }
        }
        XCTAssertTrue(bad.isEmpty, bad.joined(separator: "; "))
    }

    func testFilletIsDrawnOnTheGPU() throws {
        guard LiquidSurface.isSupported else { throw XCTSkip("no Metal") }
        let size = CGSize(width: 400, height: 300)
        let surface = LiquidSurface(frame: CGRect(origin: .zero, size: size))
        let bytes = try XCTUnwrap(surface.renderOffscreen(scene(), size: size))
        func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * 400 + x) * 4 + 3] }
        XCTAssertGreaterThan(alpha(116, 285), 200, "fillet left of the launcher's foot")
        XCTAssertLessThan(alpha(60, 285), 20, "flat band far from it")
    }

    func testDrawerSlidesOutThroughItsEdge() {
        let s = LiquidSurface(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let r = CGRect(x: 100, y: 200, width: 200, height: 90)
        XCTAssertEqual(s.slid(r, edge: .bottom, offset: 1), r.offsetBy(dx: 0, dy: 90))
        XCTAssertEqual(s.slid(r, edge: .top, offset: 0.5), r.offsetBy(dx: 0, dy: -45))
        XCTAssertEqual(s.slid(r, edge: .right, offset: 1), r.offsetBy(dx: 200, dy: 0))
        XCTAssertEqual(s.slid(r, edge: .left, offset: 0), r)
    }

    func testDrawerStylesMatchCaelestia() {
        XCTAssertEqual(ShellController.blobStyle("dashboard").edge, .top)
        XCTAssertEqual(ShellController.blobStyle("dashboard").deform, 0.1)
        XCTAssertEqual(ShellController.blobStyle("osd").deform, 0.25)
        XCTAssertEqual(ShellController.blobStyle("session").edge, .right)
        XCTAssertEqual(ShellController.blobStyle("sidebar").deform, 0.03)
        XCTAssertEqual(ShellController.blobStyle("launcher").edge, .bottom)
        XCTAssertEqual(ShellController.blobStyle("popout").edge, .left)
    }
}

@MainActor
final class ShellMotionTokenTests: XCTestCase {
    func testShellTokensAreCaelestiasAtGabbysScale() {
        let t = ShellTheme(scheme: ShellTheme.gabby.scheme)
        XCTAssertEqual(t.durationScale, 0.8, accuracy: 1e-9)
        XCTAssertEqual(t.tokenSeconds(CaelestiaTokens.Duration.defaultSpatial), 0.4, accuracy: 1e-9)
        XCTAssertEqual(t.tokenSeconds(CaelestiaTokens.Duration.fastSpatial), 0.28, accuracy: 1e-9)
        XCTAssertEqual(t.tokenSeconds(CaelestiaTokens.Duration.slowSpatial), 0.52, accuracy: 1e-9)
        XCTAssertEqual(t.tokenSeconds(CaelestiaTokens.Duration.defaultEffects), 0.16, accuracy: 1e-9)
    }

    func testReduceMotionShortensEverySurfaceAnimation() {
        var c = Config()
        c.animations.reduceMotion = true
        let t = ShellTheme(scheme: ShellTheme.gabby.scheme, config: c)
        XCTAssertTrue(t.reduceMotion)
        XCTAssertLessThanOrEqual(t.seconds(CaelestiaTokens.Duration.defaultSpatial), 0.12)
    }

    func testFrameSurfacePicksUpTheTokens() throws {
        guard LiquidSurface.isSupported else { throw XCTSkip("no Metal") }
        var t = ShellTheme(scheme: ShellTheme.gabby.scheme)
        t.liquidSurface = true
        let layout = DisplayLayout(area: CGRect(x: 0, y: 0, width: 800, height: 500), thickness: 10, barWidth: 60)
        let f = ScreenFrameWindow(displayID: "t", layout: layout, theme: t)
        defer { f.close() }
        let s = try XCTUnwrap(f.surface)
        XCTAssertEqual(s.openSeconds, 0.4, accuracy: 1e-9)
        XCTAssertEqual(s.closeSeconds, 0.4, accuracy: 1e-9)
        XCTAssertEqual(s.frameInner, CGRect(x: 10, y: 10, width: 780, height: 480))
        f.setBarReveal(1)
        XCTAssertEqual(s.frameInner.minX, 60, accuracy: 1e-9, "the bar is the frame's left edge")
    }
}
