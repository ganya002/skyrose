import Foundation

/// A CSS-style cubic Bézier easing curve from (0,0) to (1,1) with control points (x1,y1) and
/// (x2,y2). `x1`/`x2` are clamped to 0...1 so the curve is a function of time; the y control
/// points are unrestricted, so curves like `snappy` may overshoot above 1 (the output is never
/// clamped).
public struct CubicBezier: Sendable, Hashable, Codable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    /// Creates a curve. `x1` and `x2` are clamped to 0...1 (as CSS does); y values are kept as is.
    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = min(max(x1, 0), 1)
        self.y1 = y1
        self.x2 = min(max(x2, 0), 1)
        self.y2 = y2
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x1: try c.decode(Double.self, forKey: .x1), y1: try c.decode(Double.self, forKey: .y1),
            x2: try c.decode(Double.self, forKey: .x2), y2: try c.decode(Double.self, forKey: .y2))
    }

    // MARK: Named curves (SPEC section 2.2)

    /// Hyprland's built-in default: 0.00, 0.75, 0.15, 1.00.
    public static let `default` = CubicBezier(x1: 0.00, y1: 0.75, x2: 0.15, y2: 1.00)
    /// Material 3 standard easing: 0.20, 0.00, 0.00, 1.00.
    public static let standard = CubicBezier(x1: 0.20, y1: 0.00, x2: 0.00, y2: 1.00)
    /// Material 3 emphasized-decelerate (entering elements): 0.05, 0.70, 0.10, 1.00.
    public static let emphasizedDecel = CubicBezier(x1: 0.05, y1: 0.70, x2: 0.10, y2: 1.00)
    /// Material 3 emphasized-accelerate (exiting elements): 0.30, 0.00, 0.80, 0.15.
    public static let emphasizedAccel = CubicBezier(x1: 0.30, y1: 0.00, x2: 0.80, y2: 0.15)
    /// Caelestia's special-workspace switch curve: 0.05, 0.70, 0.10, 1.00.
    public static let specialWorkSwitch = CubicBezier(x1: 0.05, y1: 0.70, x2: 0.10, y2: 1.00)
    /// Gabby's workspace curve with a slight overshoot: 0.05, 0.90, 0.10, 1.05.
    public static let snappy = CubicBezier(x1: 0.05, y1: 0.90, x2: 0.10, y2: 1.05)
    /// Identity easing: 0, 0, 1, 1.
    public static let linear = CubicBezier(x1: 0, y1: 0, x2: 1, y2: 1)

    /// Every named curve in table order, keyed by its config name.
    public static let namedCurves: KeyValuePairs<String, CubicBezier> = [
        "default": .default,
        "standard": .standard,
        "emphasizedDecel": .emphasizedDecel,
        "emphasizedAccel": .emphasizedAccel,
        "specialWorkSwitch": .specialWorkSwitch,
        "snappy": .snappy,
        "linear": .linear,
    ]

    /// The config names of all named curves, in table order.
    public static var names: [String] { namedCurves.map(\.key) }

    /// Looks a curve up by its config name. Matching ignores case, spaces, `-` and `_`
    /// ("emphasizedDecel", "emphasizeddecel" and "emphasized-decel" all resolve).
    public static func named(_ name: String) -> CubicBezier? {
        let key = normalize(name)
        guard !key.isEmpty else { return nil }
        return namedCurves.first { normalize($0.key) == key }?.value
    }

    /// The config name of this curve when it is one of the named curves. Names that share the
    /// same control points (`emphasizedDecel` / `specialWorkSwitch`) resolve to the first one in
    /// table order.
    public var name: String? {
        CubicBezier.namedCurves.first { $0.value == self }?.key
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }

    // MARK: Evaluation

    /// Solver tolerance on the x axis.
    static let precision = 1e-9

    /// Eased output for an input time fraction `t`. `t` is clamped to 0...1 and the endpoints are
    /// exact (0 → 0, 1 → 1). The parameter u with x(u) = t is found with Newton's method and a
    /// bisection fallback (|x(u) − t| < 1e-9); the result is y(u), unclamped so overshooting
    /// curves overshoot.
    public func value(at t: Double) -> Double {
        if t <= 0 || t.isNaN { return 0 }
        if t >= 1 { return 1 }
        return sampleY(solveParameter(forX: t))
    }

    /// Polynomial coefficients of x(u) = ((ax·u + bx)·u + cx)·u.
    private var cx: Double { 3 * x1 }
    private var bx: Double { 3 * (x2 - x1) - cx }
    private var ax: Double { 1 - cx - bx }
    private var cy: Double { 3 * y1 }
    private var by: Double { 3 * (y2 - y1) - cy }
    private var ay: Double { 1 - cy - by }

    private func sampleX(_ u: Double) -> Double { ((ax * u + bx) * u + cx) * u }
    private func sampleY(_ u: Double) -> Double { ((ay * u + by) * u + cy) * u }
    private func sampleDerivativeX(_ u: Double) -> Double { (3 * ax * u + 2 * bx) * u + cx }

    private func solveParameter(forX x: Double) -> Double {
        let eps = CubicBezier.precision
        var u = x
        for _ in 0..<8 {
            let dx = sampleX(u) - x
            if abs(dx) < eps { return u }
            let d = sampleDerivativeX(u)
            if abs(d) < 1e-6 { break }
            u -= dx / d
        }
        var lo = 0.0
        var hi = 1.0
        u = x
        while lo < hi {
            let sx = sampleX(u)
            if abs(sx - x) < eps { return u }
            if x > sx { lo = u } else { hi = u }
            let next = (hi - lo) * 0.5 + lo
            if next == u { break }
            u = next
        }
        return u
    }
}
