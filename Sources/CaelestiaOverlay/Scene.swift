import CaelestiaCore
import CoreGraphics
import Foundation

/// What the overlay must draw, as computed by the WM after a layout pass. Frames are global AX /
/// CG coordinates (origin top-left of the primary display, y down), the same space the WM uses.
///
/// R2 contract (spec 12.2): after a scene is applied and its vanish animations have run, the
/// overlay owns exactly one border window per entry of `borders` and nothing else.
public struct OverlayScene: Equatable, Sendable {
    public var borders: [BorderTarget]
    /// How borders that are no longer in `borders` leave. Missing entries fade out.
    public var vanish: [CGWindowID: Vanish]

    public init(borders: [BorderTarget] = [], vanish: [CGWindowID: Vanish] = [:]) {
        self.borders = borders
        self.vanish = vanish
    }

    public var ids: Set<CGWindowID> { Set(borders.map(\.id)) }
}

/// One border: the frame drawn around a managed window.
public struct BorderTarget: Equatable, Sendable {
    /// The managed window (CGWindowID); the border window is ordered just above it.
    public var id: CGWindowID
    /// Border frame: the window frame grown by the border size (and the group bar strip).
    public var frame: CGRect
    public var isActive: Bool
    /// How the border shows up the first time this id appears.
    public var appear: Appear
    /// How a changed frame is reached.
    public var motion: Motion
    /// Tab bar for a window that is a member of a tab group.
    public var group: GroupBar?

    public init(id: CGWindowID, frame: CGRect, isActive: Bool, appear: Appear = .popIn, motion: Motion = .animate, group: GroupBar? = nil) {
        self.id = id
        self.frame = frame
        self.isActive = isActive
        self.appear = appear
        self.motion = motion
        self.group = group
    }
}

public enum Appear: Equatable, Sendable {
    /// New window: scale up from 80 % and fade in on `windowsIn` (riko spring).
    case popIn
    /// Already known window coming back (workspace switch, group tab): show at once.
    case instant
}

public enum Motion: Equatable, Sendable {
    /// WM retile: follow `windowsMove` (riko spring), retargeting smoothly mid-flight.
    case animate
    /// The user or the app moves the window (drag, floating move): track it 1:1.
    case snap
}

public enum Vanish: Equatable, Sendable {
    /// Closed / minimized window: shrink and fade on `windowsOut` (emphasizedAccel 240 ms).
    case fadeOut
    /// Hidden by a workspace switch or a group tab change: gone at once.
    case instant
}

/// Hyprland group bar: one tab per member, the active one highlighted.
public struct GroupBar: Equatable, Sendable {
    public var titles: [String]
    public var activeIndex: Int
    public var isLocked: Bool

    public init(titles: [String], activeIndex: Int, isLocked: Bool = false) {
        self.titles = titles
        self.activeIndex = activeIndex
        self.isLocked = isLocked
    }
}

/// Colors and geometry of the decorations (spec 1.2 / 1.5).
public struct OverlayStyle: Equatable, Sendable {
    public var borderWidth: Double
    public var cornerRadius: Double
    public var active: RGBA
    public var inactive: RGBA
    /// Group bar: height of a tab, gap between tabs, gap between bar and window, tab rounding.
    public var groupBarHeight: Double
    public var groupBarGapsIn: Double
    public var groupBarGapsOut: Double
    public var groupBarRounding: Double
    public var groupBarFontSize: Double
    public var groupBarFont: [String]
    public var groupActive: RGBA
    public var groupInactive: RGBA
    public var groupLockedActive: RGBA
    public var groupLockedInactive: RGBA
    public var groupText: RGBA
    /// Fill of the workspace-slide gap and of the cross-fade cover (surfaceContainer).
    public var surface: RGBA

    /// Strip reserved above a grouped window (bar + gap to the window).
    public var groupBarReserved: Double { groupBarHeight + groupBarGapsOut }

    public init(scheme: Scheme, wm: WMConfig = WMConfig(), fonts: [String] = ["JetBrainsMono Nerd Font", "JetBrains Mono", "Menlo"]) {
        borderWidth = wm.borderSize
        cornerRadius = wm.windowRounding
        active = scheme.activeBorder
        inactive = scheme.inactiveBorder
        groupBarHeight = wm.groupBarHeight
        groupBarGapsIn = wm.groupBarGaps
        groupBarGapsOut = wm.groupBarGaps
        groupBarRounding = 5
        groupBarFontSize = 15
        groupBarFont = fonts
        groupActive = scheme.groupBarActive
        groupInactive = scheme.groupBarInactive
        groupLockedActive = scheme.groupBarLockedActive
        groupLockedInactive = scheme.groupBarLockedInactive
        groupText = scheme[.onPrimary]
        surface = scheme.desktopBackground
    }

    /// Gabby's "current" scheme (periwinkle #bac5ee active, #a9aab5 @ 7 % inactive).
    public static let gabby = OverlayStyle(scheme: SchemeLoader.builtIn(named: "caelestia-dynamic-dark") ?? OverlayStyle.fallbackScheme)

    static let fallbackScheme = Scheme(name: "fallback", colors: [
        "primary": RGBA(hex: "bac5ee")!, "onSurfaceVariant": RGBA(hex: "a9aab5")!, "outline": RGBA(hex: "73757f")!,
        "secondary": RGBA(hex: "c1c6dd")!, "onPrimary": RGBA(hex: "333f61")!, "surfaceContainer": RGBA(hex: "181920")!,
        "inversePrimary": RGBA(hex: "525e81")!,
    ])
}

/// Group bar tab rectangles inside a border frame (top-left space): tabs share the bar width with
/// `gapsIn` between them, inset by the border on the sides, starting right under the top border.
public enum GroupBarGeometry {
    public static func tabs(count: Int, in borderFrame: CGRect, style: OverlayStyle) -> [CGRect] {
        guard count > 0 else { return [] }
        let b = style.borderWidth
        let inner = borderFrame.insetBy(dx: b, dy: b)
        let gaps = style.groupBarGapsIn * Double(count - 1)
        let width = max(0, (inner.width - gaps) / Double(count))
        return (0..<count).map { i in
            CGRect(x: inner.minX + Double(i) * (width + style.groupBarGapsIn), y: inner.minY, width: width, height: style.groupBarHeight)
        }
    }
}
