import Foundation

/// The "liquid" motion language (2026-11-05 phase): Arch/Caelestia feels bubbly because things
/// overshoot and squash, not because they are slow. Every number here keeps the hard limits:
/// springs settle (|x − 1| < 0.001) in about 300 ms, nothing runs over ~350 ms, everything is
/// interruptible (springs keep their velocity when retargeted), and Reduce Motion replaces all
/// of it with a short cross-fade (`AnimationTable.reduced`, `ShellTheme.reduceMotion`).
public enum LiquidMotion {
    /// Settling time of the liquid springs at speed 1 (seconds).
    public static let settle: Double = 0.30

    /// The spring with damping ratio `dampingRatio` that settles in `settle` seconds (mass 1).
    public static func spring(dampingRatio: Double, settle: Double) -> Spring {
        let z = min(max(dampingRatio, 0.2), 1.5)
        let k = 1000.0
        let base = Spring(mass: 1, stiffness: k, damping: 2 * z * k.squareRoot())
        let natural = base.settlingTime(epsilon: AnimationSpec.springSettlingEpsilon)
        guard natural > 0, settle > 0 else { return base }
        return base.timeScaled(by: settle / natural)
    }

    /// Damping ratio of the underdamped spring whose first peak overshoots by `fraction`.
    public static func dampingRatio(forOvershoot fraction: Double) -> Double {
        let f = min(max(fraction, 1e-4), 0.9)
        let l = log(f)
        return -l / (Double.pi * Double.pi + l * l).squareRoot()
    }

    // MARK: Windows

    /// Window pop-in: ζ 0.58 (≈ 10.7 % overshoot of the 80 % → 100 % scale, so it swells to
    /// ≈ 102 % and settles), 300 ms.
    public static let windowPop = spring(dampingRatio: 0.58, settle: settle)
    /// Retile / move / resize: ζ 0.72 (≈ 3.9 % overshoot), 300 ms. A slight swing past the slot.
    public static let windowMove = spring(dampingRatio: 0.72, settle: settle)

    // MARK: Shell drawers

    /// How far a drawer swings past its final size, in points, whatever its size: a small OSD
    /// and the big dashboard bounce by about the same visible amount.
    public static let bouncePoints: Double = 16
    /// The overshoot fraction is kept between these (tiny drawers would otherwise wobble).
    public static let minOvershoot: Double = 0.025
    public static let maxOvershoot: Double = 0.08

    /// Overshoot fraction for a drawer `depth` points deep (along the edge's normal).
    public static func drawerOvershoot(depth: Double) -> Double {
        guard depth > 0 else { return maxOvershoot }
        return min(maxOvershoot, max(minOvershoot, bouncePoints / depth))
    }

    /// The drawer's growth spring, settling in `settle` seconds.
    public static func drawerSpring(depth: Double, settle: Double = LiquidMotion.settle) -> Spring {
        spring(dampingRatio: dampingRatio(forOvershoot: drawerOvershoot(depth: depth)), settle: settle)
    }

    /// Extra room a drawer's panel needs on its far side so the swing is not clipped.
    public static func overshootRoom(depth: Double) -> Double {
        (depth * drawerOvershoot(depth: depth)).rounded(.up) + 4
    }

    /// The "neck": the drawer starts this narrow along the edge and widens to its full width on a
    /// slower, critically damped spring, so the joint to the frame stretches and then settles.
    public static let neckStart: Double = 0.84
    public static func neckSpring(settle: Double = LiquidMotion.settle) -> Spring {
        spring(dampingRatio: 1, settle: settle * 1.1)
    }

    /// Scale of a hidden drawer body along the normal (0 would make the layer transform singular).
    public static let hiddenScale: Double = 0.01

    // MARK: Bar

    /// The bar's reveal: ζ 0.62 (≈ 8 % of its 60 pt width, so the band swells ≈ 5 pt), 300 ms.
    public static let barReveal = spring(dampingRatio: 0.62, settle: settle)
    /// The frame band never swells past this reveal (a fast retarget cannot overshoot more).
    public static let barSwellCap: Double = 1.12
}
