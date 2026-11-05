import CoreGraphics
import Foundation

/// Drag (mouse) or swipe (two-finger trackpad) from the right edge to open a drawer, after
/// Caelestia `modules/drawers/Interactions.qml`:
///
/// - starting on the right band within the session menu's height and moving left past
///   ``sessionThreshold`` opens the session menu (upstream `session.dragThreshold` 30);
/// - starting anywhere else on the right band and moving left past ``sidebarThreshold`` opens the
///   sidebar (upstream `sidebar.dragThreshold` 80).
///
/// The frame stays click-through: the WM only *watches* the pointer (global event monitors), so
/// nothing under the band loses a click. Each gesture fires at most once. AppKit space (y up).
public struct EdgeDrag: Equatable, Sendable {
    public enum Zone: String, Equatable, Sendable { case session, sidebar }

    public static let sessionThreshold: Double = 30
    public static let sidebarThreshold: Double = 80
    /// A drag that wanders this far vertically is a selection or a window move, not a swipe.
    public static let maxVerticalDrift: Double = 120

    public private(set) var zone: Zone?
    public private(set) var start: CGPoint = .zero
    public private(set) var fired = false
    /// Finger travel accumulated by a trackpad swipe (negative = leftwards).
    private var swipeDX: Double = 0
    private var swipeDY: Double = 0

    public init() {}

    /// Where on the right band `p` is, if anywhere. `sessionHeight` includes its fillets.
    public static func zone(at p: CGPoint, layout: DisplayLayout, barReveal: Double, sessionHeight: Double) -> Zone? {
        let area = layout.area, inner = layout.inner(barReveal: barReveal)
        // The band, plus a 2 pt grace inside it and the clamped pixel past the edge.
        guard p.x >= inner.maxX - 2, p.x <= area.maxX + 1, p.y >= inner.minY, p.y <= inner.maxY else { return nil }
        let half = sessionHeight / 2
        return abs(p.y - inner.midY) <= half ? .session : .sidebar
    }

    static func threshold(_ z: Zone) -> Double { z == .session ? sessionThreshold : sidebarThreshold }

    /// Mouse down (or the first event of a swipe) at `p`.
    public mutating func begin(at p: CGPoint, zone z: Zone?) {
        zone = z
        start = p
        fired = false
        swipeDX = 0
        swipeDY = 0
    }

    public mutating func cancel() { zone = nil }

    /// Pointer dragged to `p`: the drawer to open, once, when the drag passed its threshold.
    public mutating func drag(to p: CGPoint) -> Zone? {
        guard let z = zone, !fired else { return nil }
        if abs(p.y - start.y) > Self.maxVerticalDrift { zone = nil; return nil }
        guard start.x - p.x >= Self.threshold(z) else { return nil }
        fired = true
        return z
    }

    /// One trackpad scroll event while a swipe is tracked; `fingerDX` < 0 = fingers moving left.
    public mutating func swipe(fingerDX: Double, fingerDY: Double) -> Zone? {
        guard let z = zone, !fired else { return nil }
        swipeDX += fingerDX
        swipeDY += fingerDY
        if abs(swipeDY) > Self.maxVerticalDrift || abs(swipeDY) > abs(swipeDX) * 1.5 + 20 { zone = nil; return nil }
        guard -swipeDX >= Self.threshold(z) else { return nil }
        fired = true
        return z
    }

    public mutating func end() { zone = nil }

    /// Finger motion from a scroll event's deltas: with natural scrolling the deltas follow the
    /// fingers; without it they are reversed.
    public static func fingerDelta(scrollingDeltaX dx: Double, invertedFromDevice: Bool) -> Double {
        invertedFromDevice ? dx : -dx
    }
}
