import Foundation
import CoreGraphics

/// Cardinal direction used by focus/move binds (Hyprland `movefocus l/r/u/d`).
public enum Direction: String, Codable, Sendable, CaseIterable {
    case left, right, up, down

    public var opposite: Direction {
        switch self {
        case .left: return .right
        case .right: return .left
        case .up: return .down
        case .down: return .up
        }
    }

    public var isHorizontal: Bool { self == .left || self == .right }
}

/// Screen edge used by bar position, drawers and reserved zones.
public enum Edge: String, Codable, Sendable, CaseIterable {
    case left, right, top, bottom
}

/// Per-edge insets in points. Order matches Hyprland's `reserved` array (top, right, bottom, left
/// in hyprctl monitors is actually [left, top, right, bottom]); we keep named fields to avoid confusion.
public struct Insets: Equatable, Hashable, Codable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = Insets()

    public static func uniform(_ v: Double) -> Insets { Insets(top: v, left: v, bottom: v, right: v) }

    public static func + (a: Insets, b: Insets) -> Insets {
        Insets(top: a.top + b.top, left: a.left + b.left, bottom: a.bottom + b.bottom, right: a.right + b.right)
    }

    public var horizontal: Double { left + right }
    public var vertical: Double { top + bottom }
}

extension CGRect {
    /// Shrinks the rect by the given insets (top-left coordinate space agnostic: `top` always
    /// removes from `minY`). Only use with rects already expressed in top-left space, or with
    /// symmetric insets.
    public func insetBy(_ insets: Insets) -> CGRect {
        CGRect(
            x: minX + insets.left,
            y: minY + insets.top,
            width: max(0, width - insets.horizontal),
            height: max(0, height - insets.vertical)
        )
    }

    /// Rounds origin and size to whole points (AX positions are integral on macOS anyway).
    public var integralPoints: CGRect {
        CGRect(x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded())
    }

    public var center: CGPoint { CGPoint(x: midX, y: midY) }

    /// True when the rects differ by at most `tolerance` points on any component.
    public func approximatelyEquals(_ other: CGRect, tolerance: Double = 1.0) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

/// The ONE converter between AppKit (bottom-left origin, y up, origin at the primary display's
/// bottom-left) and Core Graphics / Accessibility (top-left origin, y down, origin at the primary
/// display's top-left) global coordinate spaces.
///
/// Both spaces share the x axis. The primary display is the NSScreen whose frame origin is (0,0)
/// in AppKit space; its height is the only value needed to flip y for EVERY display, including
/// displays with negative origins (left of / below the primary one).
public struct CoordinateConverter: Equatable, Sendable {
    /// Height of the primary display in points (NSScreen.screens[0].frame.height).
    public let primaryHeight: Double

    public init(primaryHeight: Double) {
        self.primaryHeight = primaryHeight
    }

    /// AppKit (bottom-left) rect -> CG/AX (top-left) rect.
    public func toTopLeft(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// CG/AX (top-left) rect -> AppKit (bottom-left) rect.
    public func toBottomLeft(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.minY - r.height, width: r.width, height: r.height)
    }

    /// AppKit point -> CG/AX point.
    public func toTopLeft(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// CG/AX point -> AppKit point.
    public func toBottomLeft(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}

/// A display as the layout engine sees it. All rects are in CG/AX top-left global space.
public struct DisplayInfo: Equatable, Hashable, Sendable, Identifiable {
    /// Stable identifier (CGDisplayCreateUUIDFromDisplayID string), survives reconnects.
    public var id: String
    /// CGDirectDisplayID at the time of enumeration.
    public var displayID: UInt32
    public var name: String
    /// Full frame in top-left space.
    public var frame: CGRect
    /// Space taken by the macOS menu bar at the top (0 when hidden). On notched Macs this is the
    /// safe-area top inset, which is never usable.
    public var menuBarHeight: Double
    /// Space taken by the Dock (0 when auto-hidden), on the edge where the Dock lives.
    public var dockInsets: Insets
    public var scale: Double
    public var isPrimary: Bool
    /// The Mac's own panel (`CGDisplayIsBuiltin`): its physical corners are rounded.
    public var isBuiltIn: Bool
    /// The panel has a camera housing (non-zero top safe area), shown menu bar or not. Notched
    /// MacBook panels have rounded top corners.
    public var hasNotch: Bool
    /// Height of a menu bar that is always shown (auto-hide off). The screen frame starts below
    /// it. 0 when the menu bar auto-hides.
    public var shownMenuBarHeight: Double
    /// Hardware cutouts (the notch, or any future shape macOS reports) in global top-left space,
    /// as the parts of the top safe-area strip not covered by `NSScreen.auxiliaryTopLeftArea` /
    /// `auxiliaryTopRightArea`. Empty on displays without one and when a shown menu bar covers
    /// the strip anyway. The screen frame wraps around each cutout.
    public var topCutouts: [CGRect]

    public init(
        id: String, displayID: UInt32 = 0, name: String = "", frame: CGRect,
        menuBarHeight: Double = 0, dockInsets: Insets = .zero, scale: Double = 1, isPrimary: Bool = false,
        shownMenuBarHeight: Double = 0, topCutouts: [CGRect] = [], isBuiltIn: Bool = false, hasNotch: Bool = false
    ) {
        self.isBuiltIn = isBuiltIn
        self.hasNotch = hasNotch
        self.shownMenuBarHeight = shownMenuBarHeight
        self.topCutouts = topCutouts
        self.id = id
        self.displayID = displayID
        self.name = name
        self.frame = frame
        self.menuBarHeight = menuBarHeight
        self.dockInsets = dockInsets
        self.scale = scale
        self.isPrimary = isPrimary
    }

    /// Usable area = frame − menu bar − Dock − the shell's reserved zones (screen frame, persistent bar).
    public func usableArea(reserved: Insets) -> CGRect {
        let system = Insets(top: menuBarHeight, left: 0, bottom: 0, right: 0) + dockInsets
        return frame.insetBy(system + reserved)
    }
}
