import CaelestiaCore
import CoreGraphics
import Foundation

/// One animated scalar driven by an `AnimationSpec`. Springs keep their velocity when retargeted
/// mid-flight (a retile during a retile bends smoothly instead of restarting from rest); bezier
/// curves restart from the current value. Pure: every call takes the clock reading.
public struct AnimatedValue: Equatable, Sendable {
    public private(set) var from: Double
    public private(set) var to: Double
    public private(set) var start: TimeInterval
    public private(set) var velocity: Double
    public private(set) var spec: AnimationSpec

    public init(_ value: Double) {
        from = value
        to = value
        start = 0
        velocity = 0
        spec = .disabled
    }

    /// Value at `now` (exactly `to` once finished).
    public func value(at now: TimeInterval) -> Double {
        let t = now - start
        guard spec.enabled, spec.durationMs > 0, !spec.isFinished(at: t) else { return to }
        switch spec.curve {
        case .spring(let s): return s.position(at: t, from: from, to: to, initialVelocity: velocity)
        case .bezier(let b): return Interpolation.lerp(from, to, b.value(at: max(0, t) / spec.duration))
        }
    }

    /// Velocity (units/s) at `now`; 0 for bezier curves and finished animations.
    public func currentVelocity(at now: TimeInterval) -> Double {
        let t = now - start
        guard spec.enabled, spec.durationMs > 0, !spec.isFinished(at: t), case .spring(let s) = spec.curve else { return 0 }
        return s.velocity(at: t, from: from, to: to, initialVelocity: velocity)
    }

    public func isDone(at now: TimeInterval) -> Bool {
        !spec.enabled || spec.durationMs <= 0 || spec.isFinished(at: now - start)
    }

    /// Animates from the current value towards `target`. Same target: no change.
    public mutating func animate(to target: Double, spec: AnimationSpec, at now: TimeInterval) {
        guard target != to else { return }  // already there, or already heading there
        let current = value(at: now)
        let v = currentVelocity(at: now)
        from = current
        to = target
        start = now
        velocity = v
        self.spec = spec
    }

    /// Jumps to `target` with no animation.
    public mutating func set(_ target: Double) {
        from = target
        to = target
        velocity = 0
        spec = .disabled
    }
}

/// The drawable state of one border at one instant.
public struct BorderSample: Equatable, Sendable {
    public var frame: CGRect
    public var alpha: Double
    public var scale: Double
    /// 0 = inactive color, 1 = active color.
    public var activeMix: Double

    public init(frame: CGRect, alpha: Double, scale: Double, activeMix: Double) {
        self.frame = frame
        self.alpha = alpha
        self.scale = scale
        self.activeMix = activeMix
    }
}

/// The animation state of one border: pop-in (scale + alpha) on `windowsIn`, fade-out on
/// `windowsOut`, the active/inactive color blend on `border`, and the move fade.
///
/// Move fade (no trailing borders): in Standard mode real windows snap to their new frame, so a
/// border that springs after them trails for ~0.5 s. Instead, when the frame changes (a retile, a
/// drag, an app resizing itself) the border fades out where it is, stays hidden while the window
/// keeps moving, and once the frame has been still for `moveSettle` it jumps to the final frame
/// while invisible and fades back in. The frame channels are never interpolated.
public struct BorderAnimator: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case shown, vanishing }

    public private(set) var target: BorderTarget
    public private(set) var phase: Phase = .shown
    var x: AnimatedValue
    var y: AnimatedValue
    var w: AnimatedValue
    var h: AnimatedValue
    var alpha: AnimatedValue
    var scale: AnimatedValue
    var mix: AnimatedValue
    /// 1 = visible, 0 = hidden for a move (multiplies `alpha`).
    var moveFade = AnimatedValue(1)
    /// While hidden for a move: when to jump to `target.frame` and fade back in.
    public private(set) var revealAt: TimeInterval?

    /// Fade-out when a move starts, fade-in at the final frame, and how long the frame must stay
    /// unchanged before the border comes back (covers AX echo + the app's redraw).
    public static let moveFadeOut = AnimationSpec.bezier(.standard, milliseconds: 70)
    public static let moveFadeIn = AnimationSpec.bezier(.standard, milliseconds: 140)
    public static let moveSettle: TimeInterval = 0.15

    /// True while the border is hidden (or hiding) for a move.
    public var isHiddenForMove: Bool { revealAt != nil }

    public init(_ target: BorderTarget, table: AnimationTable, at now: TimeInterval) {
        self.target = target
        x = AnimatedValue(target.frame.minX)
        y = AnimatedValue(target.frame.minY)
        w = AnimatedValue(target.frame.width)
        h = AnimatedValue(target.frame.height)
        mix = AnimatedValue(target.isActive ? 1 : 0)
        let popIn = table[.windowsIn]
        if target.appear == .popIn, popIn.enabled, popIn.durationMs > 0 {
            var from = 0.8
            if case .popin(let s) = popIn.style { from = s }
            if case .fade = popIn.style { from = 1 }
            alpha = AnimatedValue(0)
            scale = AnimatedValue(from)
            alpha.animate(to: 1, spec: Self.fadeSpec(for: popIn), at: now)
            scale.animate(to: 1, spec: popIn, at: now)
        } else {
            alpha = AnimatedValue(1)
            scale = AnimatedValue(1)
        }
    }

    /// A spring's alpha would overshoot past 1 and back; opacity uses the spring's duration on the
    /// standard curve instead so it never blinks.
    static func fadeSpec(for spec: AnimationSpec) -> AnimationSpec {
        guard case .spring = spec.curve else { return spec }
        return .bezier(.standard, milliseconds: min(spec.durationMs, 300))
    }

    /// Applies a new target (same window). A border that was vanishing comes back.
    public mutating func update(_ new: BorderTarget, table: AnimationTable, at now: TimeInterval) {
        let wasVanishing = phase == .vanishing
        if wasVanishing {
            phase = .shown
            alpha.animate(to: 1, spec: Self.fadeSpec(for: table[.windowsIn]), at: now)
            scale.animate(to: 1, spec: table[.windowsIn], at: now)
        }
        let frameChanged = new.frame != target.frame
        if new.isActive != target.isActive {
            mix.animate(to: new.isActive ? 1 : 0, spec: table[.border], at: now)
        }
        let newFrame = new.frame
        target = new
        target.frame = shownFrameTarget
        if frameChanged {
            if wasVanishing || !Self.fades(table) {
                snap(to: newFrame)
            } else {
                hideForMove(to: newFrame, at: now)
            }
        }
    }

    /// Where `target.frame` points right now (the frame drawn, or the pending one while hidden).
    private var shownFrameTarget: CGRect { pendingFrame ?? CGRect(x: x.to, y: y.to, width: w.to, height: h.to) }
    private var pendingFrame: CGRect?

    /// The move fade runs whenever window motion is animated at all (off in game mode, with
    /// Reduce Motion and with the `off` preset: then the border simply snaps with the window).
    static func fades(_ table: AnimationTable) -> Bool {
        let move = table[.windowsMove]
        return move.enabled && move.durationMs > 0
    }

    /// The window is moving to `frame`: fade out in place (once), and push the reveal back.
    mutating func hideForMove(to frame: CGRect, at now: TimeInterval) {
        if revealAt == nil {
            moveFade.animate(to: 0, spec: Self.moveFadeOut, at: now)
        }
        pendingFrame = frame
        target.frame = frame
        revealAt = now + max(Self.moveSettle, Self.moveFadeOut.duration)
    }

    /// Reveals borders whose window has been still long enough: jump to the final frame (while
    /// invisible) and fade in. Returns true when something was revealed.
    @discardableResult
    public mutating func advance(at now: TimeInterval) -> Bool {
        guard let at = revealAt, now >= at else { return false }
        revealAt = nil
        if let f = pendingFrame { snap(to: f) }
        pendingFrame = nil
        moveFade.animate(to: 1, spec: Self.moveFadeIn, at: now)
        return true
    }

    /// Jumps to `frame` at once (no fade): used when motion is off and after a reveal.
    public mutating func snap(to frame: CGRect) {
        pendingFrame = nil
        x.set(frame.minX)
        y.set(frame.minY)
        w.set(frame.width)
        h.set(frame.height)
        target.frame = frame
    }

    /// Starts leaving. Returns false when the border should be removed at once.
    public mutating func vanish(_ how: Vanish, table: AnimationTable, at now: TimeInterval) -> Bool {
        let out = table[.windowsOut]
        guard how == .fadeOut, out.enabled, out.durationMs > 0 else { return false }
        guard phase != .vanishing else { return true }
        phase = .vanishing
        var to = 0.8
        if case .popin(let s) = out.style { to = s }
        if case .fade = out.style { to = 1 }
        if case .none = out.style { to = 0.8 }
        alpha.animate(to: 0, spec: out, at: now)
        scale.animate(to: to, spec: out, at: now)
        return true
    }

    public func sample(at now: TimeInterval) -> BorderSample {
        BorderSample(
            frame: CGRect(x: x.value(at: now), y: y.value(at: now), width: max(0, w.value(at: now)), height: max(0, h.value(at: now))),
            alpha: min(1, max(0, alpha.value(at: now))) * min(1, max(0, moveFade.value(at: now))),
            scale: scale.value(at: now),
            activeMix: min(1, max(0, mix.value(at: now)))
        )
    }

    /// Nothing moves any more.
    public func isIdle(at now: TimeInterval) -> Bool {
        revealAt == nil && [x, y, w, h, alpha, scale, mix, moveFade].allSatisfy { $0.isDone(at: now) }
    }

    /// A vanishing border whose fade-out has finished.
    public func isGone(at now: TimeInterval) -> Bool {
        phase == .vanishing && alpha.isDone(at: now) && scale.isDone(at: now)
    }
}

/// All borders, diffed scene by scene. Pure and headless: the AppKit layer only draws what
/// `samples(at:)` returns and removes the windows listed by `collectGone(at:)`.
public struct OverlayEngine: Sendable {
    public private(set) var borders: [CGWindowID: BorderAnimator] = [:]
    public var table: AnimationTable

    public init(table: AnimationTable = .gabbySpringy) {
        self.table = table
    }

    /// Applies a scene. Returns the ids removed at once (no fade-out): their windows go now.
    @discardableResult
    public mutating func apply(_ scene: OverlayScene, at now: TimeInterval) -> Set<CGWindowID> {
        var removed: Set<CGWindowID> = []
        let wanted = Dictionary(scene.borders.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for (id, var b) in borders where wanted[id] == nil {
            if b.vanish(scene.vanish[id] ?? .fadeOut, table: table, at: now) {
                borders[id] = b
            } else {
                borders[id] = nil
                removed.insert(id)
            }
        }
        for (id, target) in wanted {
            if var b = borders[id] {
                b.update(target, table: table, at: now)
                borders[id] = b
            } else {
                borders[id] = BorderAnimator(target, table: table, at: now)
            }
        }
        return removed
    }

    /// The real window frame changed under us (drag, app resize): hide the border until the
    /// window is still, then show it at the final frame. Ignored for unknown ids.
    public mutating func track(_ id: CGWindowID, frame: CGRect, at now: TimeInterval) {
        guard var b = borders[id], b.phase == .shown, b.target.frame != frame else { return }
        if BorderAnimator.fades(table) { b.hideForMove(to: frame, at: now) } else { b.snap(to: frame) }
        borders[id] = b
    }

    /// Runs pending reveals (call once per frame before sampling).
    public mutating func advance(at now: TimeInterval) {
        for (id, var b) in borders where b.revealAt != nil {
            if b.advance(at: now) { borders[id] = b }
        }
    }

    /// Removes finished fade-outs and returns their ids.
    public mutating func collectGone(at now: TimeInterval) -> Set<CGWindowID> {
        let gone = Set(borders.filter { $0.value.isGone(at: now) }.keys)
        for id in gone { borders[id] = nil }
        return gone
    }

    /// Removes everything (panic / quit / game mode).
    public mutating func removeAll() -> Set<CGWindowID> {
        let all = Set(borders.keys)
        borders.removeAll()
        return all
    }

    public func samples(at now: TimeInterval) -> [CGWindowID: BorderSample] {
        borders.mapValues { $0.sample(at: now) }
    }

    /// True while any border still moves (the display link can stop when false).
    public func isAnimating(at now: TimeInterval) -> Bool {
        borders.values.contains { !$0.isIdle(at: now) }
    }

    /// Borders that are shown (not fading out): the R2 set.
    public var shownIDs: Set<CGWindowID> { Set(borders.filter { $0.value.phase == .shown }.keys) }
}
