import CoreGraphics
import Foundation

// Caelestia's liquid surface (shell @ bcbb5d5, plugin/src/Caelestia/Blobs): the screen frame and
// every drawer background are one signed-distance "blob group". Rects merge with each other and
// with the frame through a circular smooth-min, so a drawer grows out of the border with a
// concave fillet and fuses with a neighbouring drawer. Each rect also carries a velocity-driven
// "jelly" deformation (stretch along the motion, capped at 35 %).
//
// This file is the pure half: the data the shader gets, a CPU port of `blob.frag` (tests and
// hit checks), the corner-fill pre-pass (`BlobShape::applyCornerFill`) and the jelly spring
// (`BlobRect::updatePhysics`). Coordinates are points, y-down, in the surface's own space.

/// A symmetric 2×2 deformation (upstream keeps m10 == m01).
public struct BlobDeform: Equatable, Sendable {
    public var m00: Double
    public var m01: Double
    public var m11: Double

    public init(m00: Double = 1, m01: Double = 0, m11: Double = 1) {
        self.m00 = m00
        self.m01 = m01
        self.m11 = m11
    }

    public static let identity = BlobDeform()
    public var isIdentity: Bool { m00 == 1 && m01 == 0 && m11 == 1 }

    /// Inverse (row-major m00 m01 / m10 m11), identity when singular.
    public var inverse: BlobDeform {
        let det = m00 * m11 - m01 * m01
        guard abs(det) > 1e-6 else { return .identity }
        return BlobDeform(m00: m11 / det, m01: -m01 / det, m11: m00 / det)
    }

    /// Smallest eigenvalue: the SDF is scaled by it so distances stay conservative.
    public var minEigenvalue: Double {
        let halfTr = 0.5 * (m00 + m11), halfDiff = 0.5 * (m00 - m11)
        return halfTr - (halfDiff * halfDiff + m01 * m01).squareRoot()
    }

    public func apply(_ v: CGVector) -> CGVector {
        CGVector(dx: m00 * v.dx + m01 * v.dy, dy: m01 * v.dx + m11 * v.dy)
    }

    /// The same matrix as a CGAffineTransform about `center` (y-down space).
    public func transform(about center: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(a: m00, b: m01, c: m01, d: m11, tx: 0, ty: 0))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }
}

/// Per-corner radii in shader order: top-right, bottom-right, bottom-left, top-left (y-down).
public struct BlobRadii: Equatable, Sendable {
    public var topRight: Double
    public var bottomRight: Double
    public var bottomLeft: Double
    public var topLeft: Double

    public init(topRight: Double, bottomRight: Double, bottomLeft: Double, topLeft: Double) {
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
        self.topLeft = topLeft
    }

    public static func uniform(_ r: Double) -> BlobRadii { BlobRadii(topRight: r, bottomRight: r, bottomLeft: r, topLeft: r) }

    public subscript(_ i: Int) -> Double {
        get { [topRight, bottomRight, bottomLeft, topLeft][i] }
        set {
            switch i {
            case 0: topRight = newValue
            case 1: bottomRight = newValue
            case 2: bottomLeft = newValue
            default: topLeft = newValue
            }
        }
    }
}

/// One drawer background in the group.
public struct BlobRect: Equatable, Sendable {
    /// The rect at rest (before deformation), y-down.
    public var rect: CGRect
    public var radii: BlobRadii
    public var deform: BlobDeform
    /// Bit j set: never smooth-merged with rect j (upstream `exclude`).
    public var excludeMask: UInt32

    public init(rect: CGRect, radii: BlobRadii, deform: BlobDeform = .identity, excludeMask: UInt32 = 0) {
        self.rect = rect
        self.radii = radii
        self.deform = deform
        self.excludeMask = excludeMask
    }

    public var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    public var half: CGSize { CGSize(width: rect.width / 2, height: rect.height / 2) }

    /// Half extents of the deformed rect's bounding box.
    public var screenHalf: CGSize {
        CGSize(width: abs(deform.m00) * half.width + abs(deform.m01) * half.height,
               height: abs(deform.m01) * half.width + abs(deform.m11) * half.height)
    }

    /// Radii clamped to half the shorter side (`BlobRect::cornerRadii`).
    public var clampedRadii: BlobRadii {
        let maxR = min(rect.width, rect.height) / 2
        return BlobRadii(topRight: min(radii.topRight, maxR), bottomRight: min(radii.bottomRight, maxR),
                         bottomLeft: min(radii.bottomLeft, maxR), topLeft: min(radii.topLeft, maxR))
    }

    /// Corners in radius order (TR, BR, BL, TL), y-down.
    public var corners: [CGPoint] {
        [CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY)]
    }
}

/// The screen frame: everything inside `outer` and outside the rounded `inner` (upstream
/// `BlobInvertedRect`, whose outer edge is pushed 50 px past the screen to smooth closed drawers).
public struct BlobFrame: Equatable, Sendable {
    public var outer: CGRect
    public var inner: CGRect
    /// Window-side corner radii (TR, BR, BL, TL).
    public var radii: BlobRadii

    public init(outer: CGRect, inner: CGRect, radius: Double) {
        self.init(outer: outer, inner: inner, radii: .uniform(radius))
    }

    public init(outer: CGRect, inner: CGRect, radii: BlobRadii) {
        self.outer = outer
        self.inner = inner
        self.radii = radii
    }

    /// Upstream's −50 px anchor margin.
    public static let outerMargin: Double = 50
}

/// The whole group as the shader sees it.
public struct BlobScene: Equatable, Sendable {
    public var rects: [BlobRect]
    public var frame: BlobFrame?
    /// Fillet radius k (`border.smoothing`, default 20).
    public var smoothing: Double

    public init(rects: [BlobRect] = [], frame: BlobFrame? = nil, smoothing: Double = BlobSDF.defaultSmoothing) {
        self.rects = rects
        self.frame = frame
        self.smoothing = smoothing
    }

    /// The most rects the shader takes.
    public static let maxRects = 16
}

public enum BlobSDF {
    /// Caelestia `border.smoothing`.
    public static let defaultSmoothing: Double = 20
    /// The smallest radius corner fill leaves a corner (`k_minR`).
    public static let minRadius: Double = 2

    public static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    public static func sdBox(_ p: CGPoint, center c: CGPoint, half h: CGSize) -> Double {
        let dx = abs(p.x - c.x) - h.width, dy = abs(p.y - c.y) - h.height
        return hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0)
    }

    public static func sdRoundedBox(_ p: CGPoint, center c: CGPoint, half h: CGSize, radius r: Double) -> Double {
        let dx = abs(p.x - c.x) - h.width + r, dy = abs(p.y - c.y) - h.height + r
        return hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0) - r
    }

    /// Per-corner rounded box; radii in TR, BR, BL, TL order (y-down: "top" is smaller y).
    public static func sdRoundedBox4(_ p: CGPoint, center c: CGPoint, half h: CGSize, radii r: BlobRadii) -> Double {
        let px = p.x - c.x, py = p.y - c.y
        // Upstream picks (tr, br) on the right, (tl, bl) on the left, then by y.
        let right = px > 0
        let top = right ? r.topRight : r.topLeft
        let bottom = right ? r.bottomRight : r.bottomLeft
        let rr = py > 0 ? bottom : top
        let qx = abs(px) - h.width + rr, qy = abs(py) - h.height + rr
        return min(max(qx, qy), 0) + hypot(max(qx, 0), max(qy, 0)) - rr
    }

    /// Circular smooth min: the blend is a true circular arc of radius k tangent to both surfaces.
    public static func smin(_ a: Double, _ b: Double, _ k: Double) -> Double {
        max(k, min(a, b)) - hypot(max(k - a, 0), max(k - b, 0))
    }

    public static func smax(_ a: Double, _ b: Double, _ k: Double) -> Double {
        min(-k, max(a, b)) + hypot(max(a + k, 0), max(b + k, 0))
    }

    /// smax that keeps a's boundary sharp (the frame's outer edge always fills to the screen edge).
    public static func smaxSharpA(_ a: Double, _ b: Double, _ k: Double) -> Double {
        let sm = smax(a, b, k)
        let blend = (sm - max(a, b)) * smoothstep(0, k * 0.5, -a)
        return max(a, b) + blend
    }

    /// `cornerFillFactor`: a corner is squared only within ±k of a neighbour's edge.
    public static func cornerFillFactor(_ sd: Double, _ k: Double) -> Double {
        max(smoothstep(0, k, sd), smoothstep(0, -k, sd))
    }

    /// `BlobShape::applyCornerFill`: corners touching a neighbour or sitting in the border are
    /// squared, so a drawer sits flush on the band and two drawers fuse without a notch.
    public static func effectiveRadii(_ scene: BlobScene) -> [BlobRadii] {
        let k = scene.smoothing
        return scene.rects.enumerated().map { i, ri in
            var factors = [1.0, 1.0, 1.0, 1.0]
            let corners = ri.corners
            for (j, rj) in scene.rects.enumerated() where j != i && ri.excludeMask & (1 << UInt32(j)) == 0 && rj.excludeMask & (1 << UInt32(i)) == 0 {
                for c in 0..<4 {
                    factors[c] = min(factors[c], cornerFillFactor(sdBox(corners[c], center: rj.center, half: rj.half), k))
                }
            }
            if let f = scene.frame {
                let ic = CGPoint(x: f.inner.midX, y: f.inner.midY), ih = CGSize(width: f.inner.width / 2, height: f.inner.height / 2)
                for c in 0..<4 { factors[c] = min(factors[c], smoothstep(0, k, -sdBox(corners[c], center: ic, half: ih))) }
            }
            var r = ri.clampedRadii
            for c in 0..<4 { r[c] = max(r[c] * factors[c], minRadius) }
            return r
        }
    }

    /// The merged signed distance at `p` (negative inside the surface). A line-by-line port of
    /// `blob.frag` (without the per-renderer ownership test: one renderer draws everything).
    public static func distance(at p: CGPoint, scene: BlobScene) -> Double {
        let radii = effectiveRadii(scene)
        return distance(at: p, scene: scene, radii: radii)
    }

    public static func distance(at p: CGPoint, scene: BlobScene, radii: [BlobRadii]) -> Double {
        let k = scene.smoothing
        var d: [Double] = []
        d.reserveCapacity(scene.rects.count)
        for (i, r) in scene.rects.enumerated() {
            let c = r.center, sh = r.screenHalf
            if abs(p.x - c.x) > sh.width + k * 1.5 || abs(p.y - c.y) > sh.height + k * 1.5 {
                d.append(1e10)
                continue
            }
            let inv = r.deform.inverse
            let v = inv.apply(CGVector(dx: p.x - c.x, dy: p.y - c.y))
            var di = sdRoundedBox4(CGPoint(x: c.x + v.dx, y: c.y + v.dy), center: c, half: r.half, radii: radii[i])
            di *= max(r.deform.minEigenvalue, 0.01)
            if let f = scene.frame { di *= borderCompression(p, center: c, screenHalf: sh, frame: f, k: k) }
            d.append(di)
        }
        var merged = d.min() ?? 1e10
        for i in d.indices where d[i] < 1e9 {
            let mask = scene.rects[i].excludeMask
            for j in (i + 1)..<d.count where d[j] < 1e9 && mask & (1 << UInt32(j)) == 0 && max(d[i], d[j]) < k {
                merged = min(merged, smin(d[i], d[j], k))
            }
        }
        if let f = scene.frame { merged = smin(merged, frameDistance(p, scene: scene, frame: f), k) }
        return merged
    }

    /// Upstream scales a rect's SDF on the axis facing a nearby border, narrowing the blend zone
    /// there without lowering k.
    static func borderCompression(_ p: CGPoint, center c: CGPoint, screenHalf sh: CGSize, frame f: BlobFrame, k: Double) -> Double {
        let inner = f.inner
        let distY0 = (c.y + sh.height) - inner.minY
        let distY1 = inner.maxY - (c.y - sh.height)
        let distX0 = (c.x + sh.width) - inner.minX
        let distX1 = inner.maxX - (c.x - sh.width)
        let yProx = 1 - min(smoothstep(0, k, distY0), smoothstep(0, k, distY1))
        let xProx = 1 - min(smoothstep(0, k, distX0), smoothstep(0, k, distX1))
        let qx = abs(p.x - c.x) - sh.width, qy = abs(p.y - c.y) - sh.height
        let qpx = max(qx, 0), qpy = max(qy, 0)
        let cornerLen = hypot(qpx, qpy)
        let gradX = qpx / max(cornerLen, 0.001), gradY = qpy / max(cornerLen, 0.001)
        let faceY = smoothstep(-4, 4, qy - qx), faceX = 1 - faceY
        let t = smoothstep(0, 2, cornerLen)
        let xw = faceX + (gradX - faceX) * t, yw = faceY + (gradY - faceY) * t
        return 1 + (xProx * xw + yProx * yw) * 3
    }

    /// The frame's distance including the "border sinks": the inner wall recedes where a rect
    /// pushes into the band, forming the pocket a closing drawer melts into.
    static func frameDistance(_ p: CGPoint, scene: BlobScene, frame f: BlobFrame) -> Double {
        let k = scene.smoothing
        let o = f.outer, i = f.inner
        let dOuter = sdBox(p, center: CGPoint(x: o.midX, y: o.midY), half: CGSize(width: o.width / 2, height: o.height / 2)) - 1
        var dInner = sdRoundedBox4(p, center: CGPoint(x: i.midX, y: i.midY), half: CGSize(width: i.width / 2, height: i.height / 2), radii: f.radii)
        let preOff = k * (2 - 2.0.squareRoot()) * 0.5
        var sinkValue = 0.0
        for r in scene.rects {
            let c = r.center, sh = r.screenHalf
            let topPen = min(max(i.minY - (c.y + sh.height) - preOff, 0), i.minY - o.minY)
            let botPen = min(max((c.y - sh.height) - i.maxY - preOff, 0), o.maxY - i.maxY)
            let leftPen = min(max(i.minX - (c.x + sh.width) - preOff, 0), i.minX - o.minX)
            let rightPen = min(max((c.x - sh.width) - i.maxX - preOff, 0), o.maxX - i.maxX)
            let hLat = max(abs(p.x - c.x) - sh.width, 0), vLat = max(abs(p.y - c.y) - sh.height, 0)
            let topZone = 1 - smoothstep(i.minY, i.minY + k, p.y)
            let botZone = smoothstep(i.maxY - k, i.maxY, p.y)
            let leftZone = 1 - smoothstep(i.minX, i.minX + k, p.x)
            let rightZone = smoothstep(i.maxX - k, i.maxX, p.x)
            let s = k * 2
            let sink = max(max(topPen * smoothstep(s, 0, hLat) * topZone, botPen * smoothstep(s, 0, hLat) * botZone),
                           max(leftPen * smoothstep(s, 0, vLat) * leftZone, rightPen * smoothstep(s, 0, vLat) * rightZone))
            sinkValue = max(sinkValue, sink)
        }
        dInner -= sinkValue
        let minThick = min(min(i.minY - o.minY, o.maxY - i.maxY), min(i.minX - o.minX, o.maxX - i.maxX))
        let kFrame = min(max(min(k, minThick - 1), 1), k)
        return smaxSharpA(dOuter, -dInner, kFrame)
    }
}

/// The velocity jelly of one blob (`BlobRect::updatePhysics`): every frame the rect's screen
/// velocity sets a target stretch along the motion (1 + min(speed·deformScale, 0.35), with the
/// cross axis compressed by its inverse) and each matrix component chases it on an underdamped
/// spring, damping integrated implicitly so long frames never add energy.
public struct Jelly: Equatable, Sendable {
    public static let maxStretch = 0.35
    public static let defaultStiffness = 200.0
    public static let defaultDamping = 16.0
    /// Below this speed (pt/s) a resting blob stays at rest.
    public static let wakeSpeed = 5.0

    public private(set) var deform = BlobDeform.identity
    private var v00 = 0.0, v01 = 0.0, v11 = 0.0
    public private(set) var isActive = false
    private var previous: CGPoint?
    public var stiffness: Double
    public var damping: Double
    /// Stretch per pt/s (upstream deformScale = deformAmount × appearance.deformScale / 10000).
    public var deformScale: Double

    public init(deformScale: Double, stiffness: Double = Jelly.defaultStiffness, damping: Double = Jelly.defaultDamping) {
        self.deformScale = deformScale
        self.stiffness = stiffness
        self.damping = damping
    }

    /// Upstream PanelBg: deformAmount × appearance.deformScale / 10000.
    public static func scale(deformAmount: Double, appearanceScale: Double = 1) -> Double {
        deformAmount * appearanceScale / 10000
    }

    /// The target matrix for a velocity (pt/s).
    public static func target(velocity v: CGVector, deformScale: Double) -> BlobDeform {
        let speed = hypot(v.dx, v.dy)
        guard speed > wakeSpeed else { return .identity }
        let stretch = 1 + min(speed * deformScale, maxStretch)
        let compress = 1 / stretch
        let c = v.dx / speed, s = v.dy / speed
        return BlobDeform(m00: stretch * c * c + compress * s * s, m01: (stretch - compress) * c * s, m11: stretch * s * s + compress * c * c)
    }

    /// Feeds the blob's centre at this frame. Returns whether it still needs frames.
    @discardableResult
    public mutating func step(center: CGPoint, dt: Double) -> Bool {
        guard let prev = previous else {
            previous = center
            return false
        }
        if dt > 0.1 || dt < 0.001 {
            previous = center
            if isActive { checkAtRest(speed: 0) }
            return isActive
        }
        let vel = CGVector(dx: (center.x - prev.x) / dt, dy: (center.y - prev.y) / dt)
        previous = center
        let speed = hypot(vel.dx, vel.dy)
        if !isActive {
            if speed < Self.wakeSpeed { return false }
            isActive = true
        }
        let t = Self.target(velocity: vel, deformScale: deformScale)
        let inv = 1 / (1 + damping * dt)
        v00 = (v00 - stiffness * (deform.m00 - t.m00) * dt) * inv
        deform.m00 += v00 * dt
        v01 = (v01 - stiffness * (deform.m01 - t.m01) * dt) * inv
        deform.m01 += v01 * dt
        v11 = (v11 - stiffness * (deform.m11 - t.m11) * dt) * inv
        deform.m11 += v11 * dt
        checkAtRest(speed: speed)
        if isActive {
            // `updatePolish`: imperceptible deformation snaps to rest.
            let delta = abs(deform.m00 - 1) + abs(deform.m01) + abs(deform.m11 - 1)
            if delta < 0.004, abs(v00) + abs(v01) + abs(v11) < 0.05, speed < Self.wakeSpeed { rest() }
        }
        return isActive
    }

    private mutating func checkAtRest(speed: Double) {
        let e = 0.002
        if abs(deform.m00 - 1) < e, abs(deform.m01) < e, abs(deform.m11 - 1) < e, abs(v00) < e, abs(v01) < e, abs(v11) < e, speed < Self.wakeSpeed {
            rest()
        }
    }

    /// Back to identity, no velocity (Reduce Motion, or a blob that just appeared).
    public mutating func rest() {
        deform = .identity
        v00 = 0; v01 = 0; v11 = 0
        isActive = false
    }

    /// Forgets the previous position (the next step only records one).
    public mutating func resetTracking() { previous = nil }
}
