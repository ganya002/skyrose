import Foundation

/// Colour maths for the dynamic-colour pipeline (spec 1.3): sRGB / XYZ / L*, CAM16 and the HCT
/// colour space (CAM16 hue and chroma + CIE L* as "tone"), the space Material You builds its tonal
/// palettes in. Pure and deterministic; no AppKit.
public enum ColorMath {
    /// 8-bit sRGB channel to linear 0...100.
    public static func linearized(_ channel: UInt8) -> Double {
        let n = Double(channel) / 255
        let v = n <= 0.040449936 ? n / 12.92 : pow((n + 0.055) / 1.055, 2.4)
        return v * 100
    }

    /// Linear 0...100 to an 8-bit sRGB channel (clamped).
    public static func delinearized(_ value: Double) -> UInt8 {
        let n = min(1, max(0, value / 100))
        let v = n <= 0.0031308 ? n * 12.92 : 1.055 * pow(n, 1 / 2.4) - 0.055
        return UInt8(min(255, max(0, (v * 255).rounded())))
    }

    public static func yFromLstar(_ lstar: Double) -> Double {
        let ke = 8.0
        if lstar > ke { return pow((lstar + 16) / 116, 3) * 100 }
        return lstar / (24389.0 / 27.0) * 100
    }

    public static func lstarFromY(_ y: Double) -> Double {
        let yn = y / 100
        let e = 216.0 / 24389.0
        if yn <= e { return 24389.0 / 27.0 * yn }
        return 116 * cbrt(yn) - 16
    }

    public static func lstar(r: UInt8, g: UInt8, b: UInt8) -> Double {
        lstarFromY(0.2126 * linearized(r) + 0.7152 * linearized(g) + 0.0722 * linearized(b))
    }

    static func xyz(r: UInt8, g: UInt8, b: UInt8) -> (Double, Double, Double) {
        let lr = linearized(r), lg = linearized(g), lb = linearized(b)
        return (
            0.41233895 * lr + 0.35762064 * lg + 0.18051042 * lb,
            0.2126 * lr + 0.7152 * lg + 0.0722 * lb,
            0.01932141 * lr + 0.11916382 * lg + 0.95034478 * lb
        )
    }

    public static func sanitizeDegrees(_ d: Double) -> Double {
        let m = d.truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }

    public static func differenceDegrees(_ a: Double, _ b: Double) -> Double {
        180 - abs(abs(a - b) - 180)
    }
}

/// CAM16 viewing conditions (sRGB, D65, 50 L* background, average surround), as Material uses.
struct ViewingConditions {
    let aw, nbb, ncb, c, nc, n, z, fl: Double
    let rgbD: (Double, Double, Double)

    static let standard: ViewingConditions = {
        let white = (95.047, 100.0, 108.883)
        let adaptingLuminance = 200 / Double.pi * ColorMath.yFromLstar(50) / 100
        let rW = 0.401288 * white.0 + 0.650173 * white.1 - 0.051461 * white.2
        let gW = -0.250268 * white.0 + 1.204414 * white.1 + 0.045854 * white.2
        let bW = -0.002079 * white.0 + 0.048952 * white.1 + 0.953127 * white.2
        let f = 1.0, c = 0.69, nc = 1.0
        let d = min(1, max(0, f * (1 - (1 / 3.6) * exp((-adaptingLuminance - 42) / 92))))
        let rgbD = (d * (100 / rW) + 1 - d, d * (100 / gW) + 1 - d, d * (100 / bW) + 1 - d)
        let k = 1 / (5 * adaptingLuminance + 1)
        let k4 = k * k * k * k
        let k4F = 1 - k4
        let fl = k4 * adaptingLuminance + 0.1 * k4F * k4F * cbrt(5 * adaptingLuminance)
        let n = ColorMath.yFromLstar(50) / white.1
        let z = 1.48 + sqrt(n)
        let nbb = 0.725 / pow(n, 0.2)
        func adapt(_ w: Double, _ d: Double) -> Double {
            let x = pow(fl * d * w / 100, 0.42)
            return 400 * x / (x + 27.13)
        }
        let aw = (40 * adapt(rW, rgbD.0) + 20 * adapt(gW, rgbD.1) + adapt(bW, rgbD.2)) / 20 * nbb
        return ViewingConditions(aw: aw, nbb: nbb, ncb: nbb, c: c, nc: nc, n: n, z: z, fl: fl, rgbD: rgbD)
    }()
}

/// CAM16 appearance of an sRGB colour: hue (degrees), chroma, lightness J.
public struct Cam16: Equatable, Sendable {
    public var hue: Double
    public var chroma: Double
    public var j: Double

    public init(r: UInt8, g: UInt8, b: UInt8) {
        let vc = ViewingConditions.standard
        let (x, y, z) = ColorMath.xyz(r: r, g: g, b: b)
        let rT = 0.401288 * x + 0.650173 * y - 0.051461 * z
        let gT = -0.250268 * x + 1.204414 * y + 0.045854 * z
        let bT = -0.002079 * x + 0.048952 * y + 0.953127 * z
        func adapt(_ t: Double, _ d: Double) -> Double {
            let v = d * t
            let af = pow(vc.fl * abs(v) / 100, 0.42)
            return (v < 0 ? -1.0 : 1.0) * 400 * af / (af + 27.13)
        }
        let rA = adapt(rT, vc.rgbD.0), gA = adapt(gT, vc.rgbD.1), bA = adapt(bT, vc.rgbD.2)
        let a = (11 * rA + -12 * gA + bA) / 11
        let bb = (rA + gA - 2 * bA) / 9
        let u = (20 * rA + 20 * gA + 21 * bA) / 20
        let p2 = (40 * rA + 20 * gA + bA) / 20
        var h = atan2(bb, a) * 180 / .pi
        h = ColorMath.sanitizeDegrees(h)
        let hr = h * .pi / 180
        let ac = p2 * vc.nbb
        let j = 100 * pow(ac / vc.aw, vc.c * vc.z)
        let eHue = 0.25 * (cos(hr + 2) + 3.8)
        let t = 50000 / 13 * eHue * vc.nc * vc.ncb * hypot(a, bb) / (u + 0.305)
        let alpha = pow(t, 0.9) * pow(1.64 - pow(0.29, vc.n), 0.73)
        hue = h
        chroma = alpha * sqrt(j / 100)
        self.j = j
    }
}

/// Hue (CAM16), chroma (CAM16) and tone (CIE L*): Material's HCT.
public struct Hct: Equatable, Sendable {
    public var hue: Double
    public var chroma: Double
    public var tone: Double

    public init(hue: Double, chroma: Double, tone: Double) {
        self.hue = hue
        self.chroma = chroma
        self.tone = tone
    }

    public init(r: UInt8, g: UInt8, b: UInt8) {
        let cam = Cam16(r: r, g: g, b: b)
        hue = cam.hue
        chroma = cam.chroma
        tone = ColorMath.lstar(r: r, g: g, b: b)
    }

    public init(_ color: RGBA) { self.init(r: color.r, g: color.g, b: color.b) }

    /// The in-gamut sRGB colour closest to this HCT. Chroma is reduced when the sRGB gamut cannot
    /// reach it at that hue and tone.
    public var rgba: RGBA {
        let (r, g, b) = HctSolver.solve(hue: hue, chroma: chroma, tone: tone)
        return RGBA(r: r, g: g, b: b)
    }
}

/// Finds the sRGB colour for a hue / chroma / tone (iterative CAM16 inversion at fixed luminance).
enum HctSolver {
    // Inverse of the (illuminant-discounted) CAM16 cone response matrix, in linear sRGB.
    private static let linrgbFromScaledDiscount: [[Double]] = [
        [1373.2198709594231, -1100.4251190754821, -7.278681089101213],
        [-271.815969077903, 559.6580465940733, -32.46047482791194],
        [1.9622899599665666, -57.173814538844006, 308.7233197812385],
    ]

    static func solve(hue: Double, chroma: Double, tone: Double) -> (UInt8, UInt8, UInt8) {
        if tone <= 0.0001 { return (0, 0, 0) }
        if tone >= 99.9999 { return (255, 255, 255) }
        let y = ColorMath.yFromLstar(tone)
        let h = ColorMath.sanitizeDegrees(hue) * .pi / 180
        if chroma < 0.5 { let v = ColorMath.delinearized(y); return (v, v, v) }
        if let exact = findByJ(hue: h, chroma: chroma, y: y) { return exact }
        // Out of gamut: the largest chroma that is reachable (bisection).
        var lo = 0.0, hi = chroma
        var best: (UInt8, UInt8, UInt8)?
        for _ in 0..<16 {
            let mid = (lo + hi) / 2
            if let c = findByJ(hue: h, chroma: mid, y: y) { best = c; lo = mid } else { hi = mid }
        }
        if let best { return best }
        let v = ColorMath.delinearized(y)
        return (v, v, v)
    }

    private static func inverseAdaptation(_ adapted: Double) -> Double {
        let a = abs(adapted)
        let base = max(0, 27.13 * a / (400 - a))
        return (adapted < 0 ? -1.0 : 1.0) * pow(base, 1 / 0.42)
    }

    private static func findByJ(hue: Double, chroma: Double, y: Double) -> (UInt8, UInt8, UInt8)? {
        let vc = ViewingConditions.standard
        var j = sqrt(y) * 11
        let tInner = 1 / pow(1.64 - pow(0.29, vc.n), 0.73)
        let eHue = 0.25 * (cos(hue + 2) + 3.8)
        let p1 = eHue * (50000.0 / 13.0) * vc.nc * vc.ncb
        let hSin = sin(hue), hCos = cos(hue)
        for round in 0..<5 {
            let jn = j / 100
            let alpha = (chroma == 0 || j == 0) ? 0 : chroma / sqrt(jn)
            let t = pow(alpha * tInner, 1 / 0.9)
            let ac = vc.aw * pow(jn, 1 / vc.c / vc.z)
            let p2 = ac / vc.nbb
            let gamma = 23 * (p2 + 0.305) * t / (23 * p1 + 11 * t * hCos + 108 * t * hSin)
            let a = gamma * hCos, b = gamma * hSin
            let rA = (460 * p2 + 451 * a + 288 * b) / 1403
            let gA = (460 * p2 - 891 * a - 261 * b) / 1403
            let bA = (460 * p2 - 220 * a - 6300 * b) / 1403
            let s = (inverseAdaptation(rA), inverseAdaptation(gA), inverseAdaptation(bA))
            let m = linrgbFromScaledDiscount
            let lr = m[0][0] * s.0 + m[0][1] * s.1 + m[0][2] * s.2
            let lg = m[1][0] * s.0 + m[1][1] * s.1 + m[1][2] * s.2
            let lb = m[2][0] * s.0 + m[2][1] * s.1 + m[2][2] * s.2
            if lr < 0 || lg < 0 || lb < 0 { return nil }
            let fnj = 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
            if fnj <= 0 { return nil }
            if round == 4 || abs(fnj - y) < 0.002 {
                if lr > 100.01 || lg > 100.01 || lb > 100.01 { return nil }
                return (ColorMath.delinearized(lr), ColorMath.delinearized(lg), ColorMath.delinearized(lb))
            }
            j -= (fnj - y) * j / (2 * fnj)
        }
        return nil
    }
}
