import CaelestiaCore
import CoreGraphics
import Foundation

/// Pure conversion from what `NSScreen` reports (AppKit bottom-left space) to the `DisplayInfo`
/// the layout engine uses (CG/AX top-left space). Kept free of AppKit so every display arrangement
/// (left/right/above/below, negative origins, notch) can be unit-tested (spec 4.6, 12.1).
public enum DisplayGeometry {
    /// Insets smaller than this are the sliver an auto-hidden Dock still reserves in
    /// `visibleFrame` (about 4 pt); they are treated as "Dock hidden" so tiles reach the edge.
    public static let autoHiddenDockSliver: Double = 6

    /// Raw facts about one screen, as AppKit reports them.
    public struct ScreenFacts: Equatable, Sendable {
        public var uuid: String
        public var displayID: UInt32
        public var name: String
        /// `NSScreen.frame` (AppKit space).
        public var frame: CGRect
        /// `NSScreen.visibleFrame` (AppKit space): frame minus menu bar and Dock when shown.
        public var visibleFrame: CGRect
        /// `NSScreen.safeAreaInsets.top`: the notch strip, never usable even with the menu bar hidden.
        public var safeAreaTop: Double
        public var scale: Double

        public init(
            uuid: String, displayID: UInt32 = 0, name: String = "", frame: CGRect, visibleFrame: CGRect,
            safeAreaTop: Double = 0, scale: Double = 1
        ) {
            self.uuid = uuid
            self.displayID = displayID
            self.name = name
            self.frame = frame
            self.visibleFrame = visibleFrame
            self.safeAreaTop = safeAreaTop
            self.scale = scale
        }
    }

    /// The converter for a set of screens: the primary is the one whose AppKit origin is (0, 0)
    /// (`NSScreen.screens[0]`); falls back to the first screen.
    public static func converter(for screens: [ScreenFacts]) -> CoordinateConverter {
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        return CoordinateConverter(primaryHeight: Double(primary?.frame.height ?? 0))
    }

    /// Builds the layout-side description of every screen, in the given order.
    public static func displays(from screens: [ScreenFacts]) -> [DisplayInfo] {
        let converter = converter(for: screens)
        return screens.map { info(for: $0, converter: converter) }
    }

    /// One screen in top-left space. The menu bar height is the top difference between frame and
    /// visible frame, never less than the notch inset; the Dock insets are the remaining
    /// differences on the left, right and bottom, ignoring the auto-hide sliver.
    public static func info(for s: ScreenFacts, converter: CoordinateConverter) -> DisplayInfo {
        let menuBar = max(0, s.frame.maxY - s.visibleFrame.maxY, s.safeAreaTop)
        func dock(_ v: Double) -> Double { v < autoHiddenDockSliver ? 0 : v }
        let dockInsets = Insets(
            top: 0,
            left: dock(s.visibleFrame.minX - s.frame.minX),
            bottom: dock(s.visibleFrame.minY - s.frame.minY),
            right: dock(s.frame.maxX - s.visibleFrame.maxX)
        )
        return DisplayInfo(
            id: s.uuid, displayID: s.displayID, name: s.name, frame: converter.toTopLeft(s.frame),
            menuBarHeight: menuBar, dockInsets: dockInsets, scale: s.scale, isPrimary: s.frame.origin == .zero
        )
    }

    /// The shell's reserved zones on a display: the screen frame on every edge plus the bar width
    /// on the left when the bar is persistent (spec 4.6).
    public static func reservedInsets(screenFrame: Double, persistentBarWidth: Double?) -> Insets {
        var r = Insets.uniform(screenFrame)
        // The bar replaces the frame band on its edge.
        if let bar = persistentBarWidth { r.left = max(screenFrame, bar) }
        return r
    }

    /// The display containing `point` (top-left space), else the one nearest to it.
    public static func display(containing point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let hit = displays.first(where: { $0.frame.contains(point) }) { return hit }
        return displays.min { distanceSquared(point, $0.frame) < distanceSquared(point, $1.frame) }
    }

    /// The display a window belongs to: the one with the largest overlap, else the nearest one to
    /// its centre.
    public static func display(for rect: CGRect, in displays: [DisplayInfo]) -> DisplayInfo? {
        let best = displays.max { overlap(rect, $0.frame) < overlap(rect, $1.frame) }
        if let best, overlap(rect, best.frame) > 0 { return best }
        return display(containing: rect.center, in: displays)
    }

    /// The neighbouring display in `direction` (for focus/move crossing display edges): among
    /// displays lying entirely on that side, the one overlapping the source's projection, then the
    /// nearest.
    public static func neighbor(of source: DisplayInfo, direction: Direction, in displays: [DisplayInfo]) -> DisplayInfo? {
        let f = source.frame
        let candidates = displays.filter { d in
            guard d.id != source.id else { return false }
            switch direction {
            case .left: return d.frame.maxX <= f.minX + 1
            case .right: return d.frame.minX >= f.maxX - 1
            case .up: return d.frame.maxY <= f.minY + 1
            case .down: return d.frame.minY >= f.maxY - 1
            }
        }
        func projects(_ d: DisplayInfo) -> Bool {
            direction.isHorizontal
                ? d.frame.minY < f.maxY && d.frame.maxY > f.minY
                : d.frame.minX < f.maxX && d.frame.maxX > f.minX
        }
        let pool = candidates.contains(where: projects) ? candidates.filter(projects) : candidates
        return pool.min { distanceSquared(f.center, $0.frame) < distanceSquared(f.center, $1.frame) }
    }

    static func overlap(_ a: CGRect, _ b: CGRect) -> Double {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    static func distanceSquared(_ p: CGPoint, _ r: CGRect) -> Double {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }
}
