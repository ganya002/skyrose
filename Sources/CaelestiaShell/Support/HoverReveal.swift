import CoreGraphics
import Foundation

/// Edge and corner hover reveals, after Caelestia `modules/drawers/Interactions.qml`:
///
/// - dashboard: the top band over the dashboard's width (± rounding);
/// - utilities: the bottom band under the utilities column (the bottom-right corner);
/// - OSD: the right band over the OSD's height (± rounding).
///
/// While a hover-opened drawer is open its zone grows to cover the drawer itself plus the
/// rounding, so moving onto it keeps it; leaving closes it. Upstream also counts `rounding` past
/// the band for the closed utilities zone; SkyRose triggers on the band only, so working near
/// the bottom of a window never pops it. All in AppKit space (y up), like `DisplayLayout`.
public enum HoverReveal {
    /// The drawers that open on hover.
    public enum Target: String, Sendable, CaseIterable { case dashboard, utilities, osd }

    /// How long the pointer must stay in a closed zone before the drawer opens: crossing the top
    /// band on the way to the menu bar must not flash the dashboard. Not in upstream.
    public static let dwell: TimeInterval = 0.1

    /// Sizes of the drawers (fillets included) as they open on this display.
    public struct Sizes: Equatable, Sendable {
        public var dashboard: CGSize
        public var utilities: CGSize
        public var osd: CGSize
        public init(dashboard: CGSize, utilities: CGSize, osd: CGSize) {
            self.dashboard = dashboard
            self.utilities = utilities
            self.osd = osd
        }
    }

    /// Whether `p` is in `target`'s zone; `open` = the drawer is showing (zone includes it).
    public static func contains(_ p: CGPoint, target: Target, layout: DisplayLayout, barReveal: Double, sizes: Sizes,
                                rounding: Double, open: Bool) -> Bool {
        let area = layout.area, inner = layout.inner(barReveal: barReveal)
        // The outer edge counts a point past the display (the pointer is clamped onto it).
        let outerTop = area.maxY + 1, outerRight = area.maxX + 1, outerBottom = area.minY - 1
        switch target {
        case .dashboard:
            let w = sizes.dashboard.width
            let x0 = inner.midX - w / 2 - rounding, x1 = inner.midX + w / 2 + rounding
            // The band's dip around a notch is band too (that is where the frame is drawn).
            let band = inner.maxY - layout.topClearance(minX: x0, maxX: x1)
            let y0 = open ? inner.maxY - sizes.dashboard.height - rounding : band
            return p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= outerTop
        case .utilities:
            let w = sizes.utilities.width
            let x0 = inner.maxX - w - (open ? rounding : 0)
            let y1 = open ? inner.minY + sizes.utilities.height + rounding : inner.minY
            return p.x >= x0 && p.x <= outerRight && p.y >= outerBottom && p.y <= y1
        case .osd:
            let h = sizes.osd.height
            let y0 = inner.midY - h / 2 - rounding, y1 = inner.midY + h / 2 + rounding
            let x0 = open ? inner.maxX - sizes.osd.width : inner.maxX
            return p.x >= x0 && p.x <= outerRight && p.y >= y0 && p.y <= y1
        }
    }
}
