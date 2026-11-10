import CoreGraphics
import Foundation

/// The four corner radii of one window, in points. Zero is a square corner.
public struct CornerRadii: Equatable, Sendable {
    public var topLeft: Double
    public var topRight: Double
    public var bottomRight: Double
    public var bottomLeft: Double

    public init(topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public init(uniform radius: Double) {
        self.init(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
    }

    public static let square = CornerRadii(uniform: 0)

    public var isSquare: Bool {
        topLeft < 0.5 && topRight < 0.5 && bottomRight < 0.5 && bottomLeft < 0.5
    }

    /// One radius when all four agree, else nil.
    public var uniform: Double? {
        let values = [topLeft, topRight, bottomRight, bottomLeft]
        guard let first = values.first, values.allSatisfy({ abs($0 - first) < 0.05 }) else { return nil }
        return first
    }

    /// Radii of a stroke whose centreline is `lineWidth` outside the window. A square corner stays square.
    public func outset(by lineWidth: Double) -> CornerRadii {
        func grow(_ r: Double) -> Double { r >= 0.5 ? r + lineWidth : 0 }
        return CornerRadii(topLeft: grow(topLeft), topRight: grow(topRight), bottomRight: grow(bottomRight), bottomLeft: grow(bottomLeft))
    }

    /// A rounded-rect path in `rect`. `rect` is the stroke's centreline box. Y increases downward
    /// (a flipped layer): top-left is `minX`, `minY`.
    public func path(in rect: CGRect) -> CGPath {
        let tl = max(0, topLeft), tr = max(0, topRight), br = max(0, bottomRight), bl = max(0, bottomLeft)
        if abs(tl - tr) < 0.05, abs(tr - br) < 0.05, abs(br - bl) < 0.05 {
            return CGPath(roundedRect: rect, cornerWidth: tl, cornerHeight: tl, transform: nil)
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + tr), radius: tr)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - br, y: rect.maxY), radius: br)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bl), radius: bl)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + tl, y: rect.minY), radius: tl)
        path.closeSubpath()
        return path
    }
}

/// Fits a corner radius from the alpha mask of a window's top-left corner.
///
/// The mask is row-major, y down, 0 outside the window. A square corner is opaque from (0, 0).
/// A radius of `r` pixels leaves the top row transparent until column `r`.
public enum CornerRadiusFit {
    public struct Mask: Equatable, Sendable {
        public var width: Int
        public var height: Int
        public var alpha: [UInt8]

        public init(width: Int, height: Int, alpha: [UInt8]) {
            self.width = width
            self.height = height
            self.alpha = alpha
        }

        public func opaque(_ x: Int, _ y: Int, at threshold: UInt8) -> Bool {
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            return alpha[y * width + x] >= threshold
        }
    }

    /// Radius in pixels. `threshold` is the alpha that counts as inside the window.
    public static func topLeftRadius(_ mask: Mask, threshold: UInt8 = 128) -> Double {
        guard mask.width > 1, mask.height > 1, mask.alpha.count >= mask.width * mask.height else { return 0 }
        // The straight top edge starts at the first opaque pixel of the top row.
        var alongTop = 0
        while alongTop < mask.width, !mask.opaque(alongTop, 0, at: threshold) { alongTop += 1 }
        var alongLeft = 0
        while alongLeft < mask.height, !mask.opaque(0, alongLeft, at: threshold) { alongLeft += 1 }
        if alongTop == 0 || alongLeft == 0 { return 0 }
        let guess = Double(min(alongTop, alongLeft))
        // Reject a guess the circle does not explain (a ragged mask): the pixel just inside the
        // guessed arc should be opaque, and the pixel just outside should not.
        let r = Int(guess.rounded())
        guard r > 0, r < mask.width, r < mask.height else { return 0 }
        let inside = mask.opaque(r, 1, at: threshold) || mask.opaque(r - 1, 1, at: threshold)
        let outside = !mask.opaque(0, 0, at: threshold)
        return inside && outside ? guess : 0
    }

    /// Radius in pixels from where the corner's diagonal enters the window. Real corners are
    /// antialiased, so the top row starts well before `r`; the diagonal is one clean crossing.
    /// Nil when the diagonal never enters the window (nothing drawn there).
    public static func diagonalRadius(_ mask: Mask, threshold: UInt8 = 128) -> Double? {
        let count = min(mask.width, mask.height)
        guard count > 1, mask.alpha.count >= mask.width * mask.height else { return nil }
        var d = 0
        while d < count, !mask.opaque(d, d, at: threshold) { d += 1 }
        guard d < count else { return nil }
        if d == 0 { return 0 }
        let before = Double(mask.alpha[(d - 1) * mask.width + d - 1])
        let after = Double(mask.alpha[d * mask.width + d])
        let t = after > before ? (Double(threshold) - before) / (after - before) : 0.5
        let crossing = Double(d - 1) + t + 0.5
        return crossing / (1 - 1 / 2.0.squareRoot())
    }

    /// All four radii, in points, from a whole window's alpha (row-major, y down). Nil when a
    /// corner has nothing drawn yet or the shape is not a corner a border could follow.
    public static func radii(alpha: [UInt8], width: Int, height: Int, scale: Double, maxPoints: Double = 64) -> CornerRadii? {
        guard width > 1, height > 1, scale > 0, alpha.count >= width * height else { return nil }
        let side = min(Int((maxPoints * scale).rounded(.up)), width / 2, height / 2)
        guard side > 1 else { return nil }
        func corner(flipX: Bool, flipY: Bool) -> Double? {
            var cut = [UInt8](repeating: 0, count: side * side)
            for y in 0..<side {
                let row = flipY ? height - 1 - y : y
                for x in 0..<side {
                    cut[y * side + x] = alpha[row * width + (flipX ? width - 1 - x : x)]
                }
            }
            guard let pixels = diagonalRadius(Mask(width: side, height: side, alpha: cut)) else { return nil }
            let points = pixels / scale
            return points <= maxPoints ? points : nil
        }
        guard let tl = corner(flipX: false, flipY: false), let tr = corner(flipX: true, flipY: false),
              let br = corner(flipX: true, flipY: true), let bl = corner(flipX: false, flipY: true) else { return nil }
        return CornerRadii(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
    }

    /// A hard quarter-circle mask (no antialiasing) for tests. Radius `r` pixels, canvas `side`.
    public static func quarterCircle(radius r: Int, side: Int) -> Mask {
        var alpha = [UInt8](repeating: 0, count: side * side)
        for y in 0..<side {
            for x in 0..<side {
                let inside: Bool
                if x >= r || y >= r {
                    inside = true
                } else {
                    let dx = Double(r - x), dy = Double(r - y)
                    inside = dx * dx + dy * dy <= Double(r * r)
                }
                alpha[y * side + x] = inside ? 255 : 0
            }
        }
        return Mask(width: side, height: side, alpha: alpha)
    }
}
