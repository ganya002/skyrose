import Foundation
import CoreGraphics

/// Linear interpolation helpers. `t` is not clamped, so overshooting curves extrapolate.
public struct Interpolation: Sendable {
    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    public static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
    }

    public static func lerp(_ a: CGSize, _ b: CGSize, _ t: Double) -> CGSize {
        CGSize(width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
    }

    public static func lerp(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        CGRect(origin: lerp(a.origin, b.origin, t), size: lerp(a.size, b.size, t))
    }
}

/// Samples one `AnimationSpec` against a clock. Pure: the caller (a CVDisplayLink/CADisplayLink
/// callback) supplies `now`; the sampler never reads a clock or owns a timer.
public struct FrameSampler: Sendable, Equatable {
    public let spec: AnimationSpec
    /// Clock reading when the animation started, in the same units as `now`.
    public let startTime: TimeInterval

    public init(spec: AnimationSpec, startTime: TimeInterval) {
        self.spec = spec
        self.startTime = startTime
    }

    /// Clock reading at which the animation finishes.
    public var endTime: TimeInterval { startTime + spec.duration }

    /// Seconds since the start (negative before it).
    public func elapsed(at now: TimeInterval) -> TimeInterval { now - startTime }

    /// Eased progress at `now`: 0 before the start, exactly 1 from `endTime` on.
    public func value(at now: TimeInterval) -> Double {
        spec.progress(at: elapsed(at: now))
    }

    /// True from `endTime` on (immediately for disabled animations).
    public func isDone(at now: TimeInterval) -> Bool {
        spec.isFinished(at: elapsed(at: now))
    }

    /// `from` → `to` eased at `now`.
    public func scalar(from: Double, to: Double, at now: TimeInterval) -> Double {
        Interpolation.lerp(from, to, value(at: now))
    }

    /// `from` → `to` eased at `now`.
    public func frame(from: CGRect, to: CGRect, at now: TimeInterval) -> CGRect {
        Interpolation.lerp(from, to, value(at: now))
    }
}
