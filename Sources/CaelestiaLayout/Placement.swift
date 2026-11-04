import Foundation
import CoreGraphics
import CaelestiaCore

/// Where one window goes. All rects are in CG/AX top-left global space, in points.
///
/// `frame` is the window's own frame (what the WM sends over AX). Hyprland stores the window size
/// EXCLUDING the border, so `borderFrame` is the border overlay drawn just outside `frame`
/// (`frame` expanded by the border size on every side). For a grouped window the strip of
/// `LayoutParams.groupBarHeight` points directly above `frame` (inside `borderFrame`) is reserved
/// for the WM's group bar.
public struct Placement: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case tiled, floating, fullscreen, maximized, pinned
    }

    public var window: WindowID
    public var frame: CGRect
    public var borderFrame: CGRect
    public var kind: Kind
    /// True for inactive members of a tab group: the WM parks them (they keep the group's frame
    /// so switching tabs is instant).
    public var hidden: Bool
    /// A tiled window whose learned minimum size does not fit in its slot even after the splits
    /// gave it every point they could (`frame` is its min size, so it overlaps a neighbour). The
    /// WM floats such a window instead of fighting the app.
    public var overflows: Bool

    public init(window: WindowID, frame: CGRect, borderFrame: CGRect, kind: Kind, hidden: Bool = false, overflows: Bool = false) {
        self.window = window
        self.frame = frame
        self.borderFrame = borderFrame
        self.kind = kind
        self.hidden = hidden
        self.overflows = overflows
    }
}

/// Gap/border parameters for one layout pass (Hyprland `general:gaps_in/gaps_out/border_size` plus
/// the Caelestia single-window rule and the dwindle knobs that influence node boxes).
public struct LayoutParams: Sendable, Equatable {
    /// Gap on each side of a tiled window towards a neighbour (5 → 10 points between windows).
    public var gapsIn: Double
    /// Gap between a tiled window and the usable-area edge.
    public var gapsOut: Double
    /// Replaces `gapsOut` when exactly one tiled visible window is on the workspace (Caelestia
    /// workspace rule `w[tv1]s[false]`). nil disables the rule (special workspaces).
    public var gapsOutSingle: Double?
    public var borderSize: Double
    /// Height reserved above a grouped window for the group bar (0 = none).
    public var groupBarHeight: Double
    /// Dwindle options that influence node boxes (`preserveSplit`, `splitWidthMultiplier`, ...).
    public var dwindle: DwindleConfig

    public init(
        gapsIn: Double = 5, gapsOut: Double = 10, gapsOutSingle: Double? = 20, borderSize: Double = 1,
        groupBarHeight: Double = 0, dwindle: DwindleConfig = DwindleConfig()
    ) {
        self.gapsIn = gapsIn
        self.gapsOut = gapsOut
        self.gapsOutSingle = gapsOutSingle
        self.borderSize = borderSize
        self.groupBarHeight = groupBarHeight
        self.dwindle = dwindle
    }

    /// Parameters from the WM config. Game mode (Caelestia `gameMode`) zeroes gaps and borders.
    /// `singleWindowGaps` is false on special workspaces (the rule is `s[false]`).
    public init(wm: WMConfig, singleWindowGaps: Bool = true, groupBarHeight: Double = 0) {
        if wm.gameMode {
            self.init(gapsIn: 0, gapsOut: 0, gapsOutSingle: nil, borderSize: 0, groupBarHeight: groupBarHeight, dwindle: wm.dwindle)
        } else {
            self.init(
                gapsIn: wm.gapsIn, gapsOut: wm.gapsOut, gapsOutSingle: singleWindowGaps ? wm.gapsOutSingle : nil,
                borderSize: wm.borderSize, groupBarHeight: groupBarHeight, dwindle: wm.dwindle
            )
        }
    }
}

/// The window edges being dragged during a mouse resize (Hyprland `eRectCorner`). Combine two
/// to drag a corner; an empty set is Hyprland's `CORNER_NONE` (keyboard resize).
public struct ResizeEdges: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let left = ResizeEdges(rawValue: 1 << 0)
    public static let right = ResizeEdges(rawValue: 1 << 1)
    public static let top = ResizeEdges(rawValue: 1 << 2)
    public static let bottom = ResizeEdges(rawValue: 1 << 3)

    public static let topLeft: ResizeEdges = [.top, .left]
    public static let topRight: ResizeEdges = [.top, .right]
    public static let bottomLeft: ResizeEdges = [.bottom, .left]
    public static let bottomRight: ResizeEdges = [.bottom, .right]

    /// The corner nearest to the pointer at drag start, like Hyprland's drag controller: the
    /// window is split into four quadrants around its centre.
    public static func nearestCorner(to point: CGPoint, in frame: CGRect) -> ResizeEdges {
        var edges: ResizeEdges = point.x < frame.midX ? .left : .right
        edges.insert(point.y < frame.midY ? .top : .bottom)
        return edges
    }
}

/// Small geometry helpers that mirror Hyprland's `CBox`/`STICKS` semantics.
enum HyprGeometry {
    /// Hyprland `STICKS(a, b)`: `abs(a − b) < 2`.
    static func sticks(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 2
    }

    /// Hyprland `CBox::round()`: rounds the origin, then rounds the far edge relative to the rounded
    /// origin so adjacent boxes keep partitioning their parent exactly.
    static func rounded(_ r: CGRect) -> CGRect {
        let x = r.minX.rounded()
        let y = r.minY.rounded()
        let w = (r.minX + r.width - x).rounded()
        let h = (r.minY + r.height - y).rounded()
        return CGRect(x: x, y: y, width: max(0, w), height: max(0, h))
    }

    /// Squared distance from a point to a rect (0 when inside), Hyprland `vecToRectDistanceSquared`.
    static func distanceSquared(from p: CGPoint, to r: CGRect) -> Double {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }

    /// Keeps `frame` inside `area`, shrinking it when it is larger than the area.
    static func clamp(_ frame: CGRect, to area: CGRect) -> CGRect {
        let w = min(frame.width, area.width)
        let h = min(frame.height, area.height)
        let x = min(max(frame.minX, area.minX), area.maxX - w)
        let y = min(max(frame.minY, area.minY), area.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Grows `frame` to at least `minimum`, keeping it centred on its own centre (origin rounded).
    static func atLeast(_ frame: CGRect, _ minimum: CGSize) -> CGRect {
        var result = frame
        if minimum.width > frame.width {
            result.size.width = minimum.width
            result.origin.x = (frame.midX - minimum.width / 2).rounded()
        }
        if minimum.height > frame.height {
            result.size.height = minimum.height
            result.origin.y = (frame.midY - minimum.height / 2).rounded()
        }
        return result
    }
}
