import Foundation

/// A damped harmonic spring (mass–stiffness–damping), solved analytically for the under-,
/// critically- and over-damped cases. Positions are expressed as a normalized 0 → 1 motion by
/// default so a spring can drive any scalar, point or rect interpolation.
///
/// Non-physical parameters are tolerated: mass and stiffness are treated as at least 1e-9 and
/// damping as at least 0, so every spring has a defined response.
public struct Spring: Sendable, Hashable, Codable {
    public let mass: Double
    public let stiffness: Double
    public let damping: Double

    public init(mass: Double, stiffness: Double, damping: Double) {
        self.mass = mass
        self.stiffness = stiffness
        self.damping = damping
    }

    /// Gabby's "riko" spring: mass 1, stiffness 180, damping 20 (ζ ≈ 0.745, ~3 % overshoot,
    /// settles within 0.001 after ≈ 0.59 s).
    public static let riko = Spring(mass: 1, stiffness: 180, damping: 20)

    /// The default window spring: mass 1, stiffness 800, damping 46 (ζ ≈ 0.81, ~1.2 % overshoot,
    /// within 2 % after ≈ 0.14 s, settles within 0.001 after ≈ 0.30 s). Riko's feel, twice as fast.
    public static let snappy = Spring(mass: 1, stiffness: 800, damping: 46)

    /// Upper bound on the settling-time search: a spring that has not settled by then (for
    /// example an undamped one) reports this value so no animation can run forever.
    public static let maxSettlingTime: Double = 10

    // MARK: Derived quantities

    private var m: Double { max(mass, 1e-9) }
    private var k: Double { max(stiffness, 1e-9) }
    private var c: Double { max(damping, 0) }

    /// Undamped angular frequency ω₀ = √(k/m), in rad/s.
    public var naturalFrequency: Double { (k / m).squareRoot() }

    /// Damping ratio ζ = c / (2·√(k·m)); < 1 underdamped, 1 critically damped, > 1 overdamped.
    public var dampingRatio: Double { c / (2 * (k * m).squareRoot()) }

    /// Damped angular frequency ω₀·√(1 − ζ²) for underdamped springs, 0 otherwise.
    public var dampedFrequency: Double {
        let z = dampingRatio
        return z < 1 ? naturalFrequency * (1 - z * z).squareRoot() : 0
    }

    public var isCriticallyDamped: Bool { abs(dampingRatio - 1) < 1e-9 }
    public var isUnderdamped: Bool { dampingRatio < 1 && !isCriticallyDamped }
    public var isOverdamped: Bool { dampingRatio > 1 && !isCriticallyDamped }

    // MARK: Response

    /// Position at time `t` (seconds) when released at `from` with `initialVelocity` (units/s)
    /// toward `to`. Returns `from` for t ≤ 0.
    public func position(at t: Double, from: Double = 0, to: Double = 1, initialVelocity: Double = 0) -> Double {
        if t <= 0 || t.isNaN { return from }
        return to + displacement(at: t, y0: from - to, v0: initialVelocity)
    }

    /// Velocity (units/s) at time `t` for the same motion as `position(at:from:to:initialVelocity:)`.
    public func velocity(at t: Double, from: Double = 0, to: Double = 1, initialVelocity: Double = 0) -> Double {
        if t <= 0 || t.isNaN { return initialVelocity }
        return displacementVelocity(at: t, y0: from - to, v0: initialVelocity)
    }

    /// Displacement y(t) = x(t) − target of the homogeneous equation y'' + 2ζω₀y' + ω₀²y = 0.
    private func displacement(at t: Double, y0: Double, v0: Double) -> Double {
        let w0 = naturalFrequency
        let z = dampingRatio
        if isCriticallyDamped {
            let b = v0 + w0 * y0
            return exp(-w0 * t) * (y0 + b * t)
        } else if z < 1 {
            let wd = w0 * (1 - z * z).squareRoot()
            let cc = (v0 + z * w0 * y0) / wd
            return exp(-z * w0 * t) * (y0 * cos(wd * t) + cc * sin(wd * t))
        } else {
            let (r1, r2, a, b) = overdampedRoots(y0: y0, v0: v0)
            return a * exp(r1 * t) + b * exp(r2 * t)
        }
    }

    private func displacementVelocity(at t: Double, y0: Double, v0: Double) -> Double {
        let w0 = naturalFrequency
        let z = dampingRatio
        if isCriticallyDamped {
            let b = v0 + w0 * y0
            return exp(-w0 * t) * (b - w0 * (y0 + b * t))
        } else if z < 1 {
            let wd = w0 * (1 - z * z).squareRoot()
            let cc = (v0 + z * w0 * y0) / wd
            let decay = exp(-z * w0 * t)
            let s = sin(wd * t)
            let co = cos(wd * t)
            return decay * ((-z * w0) * (y0 * co + cc * s) + wd * (cc * co - y0 * s))
        } else {
            let (r1, r2, a, b) = overdampedRoots(y0: y0, v0: v0)
            return a * r1 * exp(r1 * t) + b * r2 * exp(r2 * t)
        }
    }

    /// Roots r1 > r2 (both negative) and amplitudes of y = A·e^(r1·t) + B·e^(r2·t).
    private func overdampedRoots(y0: Double, v0: Double) -> (Double, Double, Double, Double) {
        let w0 = naturalFrequency
        let z = dampingRatio
        let root = (z * z - 1).squareRoot()
        let r1 = -w0 * (z - root)
        let r2 = -w0 * (z + root)
        let a = (v0 - r2 * y0) / (r1 - r2)
        return (r1, r2, a, y0 - a)
    }

    // MARK: Settling and overshoot

    /// First time after which |x(t) − 1| stays below `epsilon` for the normalized 0 → 1 motion
    /// from rest. Found with a fine numeric scan (≤ 0.5 ms steps, finer for stiff springs) up
    /// to the time where the decay envelope guarantees settling, then refined by bisection.
    /// Springs whose envelope cannot guarantee settling within `maxSettlingTime` (undamped or
    /// extremely slow ones) report `maxSettlingTime`.
    public func settlingTime(epsilon: Double = 0.001) -> Double {
        let eps = max(epsilon, 1e-12)
        let y0 = -1.0
        let v0 = 0.0
        guard abs(y0) >= eps else { return 0 }
        guard let horizon = envelopeBound(epsilon: eps, y0: y0, v0: v0), horizon <= Spring.maxSettlingTime else {
            return Spring.maxSettlingTime
        }
        let step = scanStep
        var lastOutside = 0.0
        var t = 0.0
        while t < horizon {
            if abs(displacement(at: t, y0: y0, v0: v0)) >= eps { lastOutside = t }
            t += step
        }
        var lo = lastOutside
        var hi = lastOutside + step
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if abs(displacement(at: mid, y0: y0, v0: v0)) >= eps { lo = mid } else { hi = mid }
        }
        return hi
    }

    /// Maximum amount by which the normalized 0 → 1 motion from rest exceeds its target
    /// (0 for springs that never overshoot). Found numerically: a fine scan over the first two
    /// oscillation periods (from rest the first positive peak is the largest) refined by a
    /// ternary search. Riko overshoots by ≈ 0.030.
    public var overshoot: Double {
        let y0 = -1.0
        let v0 = 0.0
        if !isUnderdamped { return 0 }
        let end = min(Spring.maxSettlingTime, 2 * (2 * .pi / dampedFrequency))
        let step = scanStep
        var best = 0.0
        var bestT = 0.0
        var t = 0.0
        while t <= end {
            let y = displacement(at: t, y0: y0, v0: v0)
            if y > best {
                best = y
                bestT = t
            }
            t += step
        }
        guard best > 0 else { return 0 }
        var lo = max(0, bestT - step)
        var hi = bestT + step
        for _ in 0..<80 {
            let m1 = lo + (hi - lo) / 3
            let m2 = hi - (hi - lo) / 3
            if displacement(at: m1, y0: y0, v0: v0) < displacement(at: m2, y0: y0, v0: v0) { lo = m1 } else { hi = m2 }
        }
        return max(best, displacement(at: (lo + hi) / 2, y0: y0, v0: v0))
    }

    /// Time after which the decay envelope guarantees |y(t)| < epsilon forever, or nil when the
    /// response never decays (no damping).
    func envelopeBound(epsilon: Double, y0: Double, v0: Double) -> Double? {
        let w0 = naturalFrequency
        let z = dampingRatio
        guard z > 0, w0 > 0 else { return nil }
        if isCriticallyDamped {
            let b = abs(v0 + w0 * y0)
            let a = abs(y0)
            // e^(−ω₀t)(a + b·t) is decreasing after t = 1/ω₀ − a/b; bisect on that tail.
            let start = b > 0 ? max(0, 1 / w0 - a / b) : 0
            return decreasingTail(from: start, below: epsilon) { exp(-w0 * $0) * (a + b * $0) }
        } else if z < 1 {
            let wd = w0 * (1 - z * z).squareRoot()
            let cc = (v0 + z * w0 * y0) / wd
            let amplitude = (y0 * y0 + cc * cc).squareRoot()
            guard amplitude > epsilon else { return 0 }
            return log(amplitude / epsilon) / (z * w0)
        } else {
            let (r1, r2, a, b) = overdampedRoots(y0: y0, v0: v0)
            return decreasingTail(from: 0, below: epsilon) { abs(a) * exp(r1 * $0) + abs(b) * exp(r2 * $0) }
        }
    }

    /// First t ≥ `start` where a decreasing, vanishing function drops below `threshold`.
    private func decreasingTail(from start: Double, below threshold: Double, _ f: (Double) -> Double) -> Double {
        if f(start) < threshold { return start }
        var hi = max(start, 1e-3)
        while f(hi) >= threshold {
            hi *= 2
            if hi > Spring.maxSettlingTime * 4 { return hi }
        }
        var lo = start
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if f(mid) >= threshold { lo = mid } else { hi = mid }
        }
        return hi
    }

    /// Scan step: 0.5 ms, or finer so an underdamped oscillation gets ≥ 200 samples per period.
    private var scanStep: Double {
        let wd = dampedFrequency
        guard wd > 0 else { return 0.0005 }
        return min(0.0005, (2 * .pi / wd) / 200)
    }

    // MARK: Time scaling

    /// The spring with the same damping ratio whose response is this one stretched in time by
    /// `factor` (2 → twice as slow). Keeps the mass: stiffness / factor², damping / factor.
    public func timeScaled(by factor: Double) -> Spring {
        guard factor > 0, factor.isFinite else { return self }
        return Spring(mass: mass, stiffness: stiffness / (factor * factor), damping: damping / factor)
    }
}
