import CoreGraphics
import Foundation

/// Layout maths for the part-2 drawers. Pure: every size derives from the display's inner rect
/// (`DisplayLayout.inner`, which already excludes the frame band, the bar and the notch strip), so
/// the drawers fit any screen, notched or external.
public enum ShellSizing {
    // Measured on 1-dashboard.jpg / 1-sidebar.jpg / 1-utilities.jpg (image px x 2 = pt, the
    // references were taken on a 5120 px wide display shown at half size).
    public static let dashboardDesign = CGSize(width: 860, height: 560)
    /// The dashboard's height on each tab: the drawer morphs between them.
    public static func dashboardHeight(_ tab: DashboardTab) -> Double {
        switch tab {
        case .overview, .weather: return dashboardDesign.height
        case .media: return 460
        case .performance: return 540
        }
    }
    public static let sidebarDesignWidth: Double = 400
    public static let popoutWidth: Double = 300
    public static let wallpaperStripHeight: Double = 196
    public static let wallpaperMaxWidth: Double = 920

    /// Uniform scale (<= 1) that makes `design` fit `available` minus `margin` on each side.
    public static func fitScale(design: CGSize, available: CGSize, margin: Double = 12) -> Double {
        guard design.width > 0, design.height > 0 else { return 1 }
        let w = (available.width - 2 * margin) / design.width
        let h = (available.height - 2 * margin) / design.height
        return max(0.3, min(1, w, h))
    }

    /// The dashboard body size after scaling, and its scale.
    public static func dashboard(inner: CGRect, fillet: Double = 25) -> (scale: Double, body: CGSize) {
        let s = fitScale(design: dashboardDesign, available: CGSize(width: inner.width - 2 * fillet, height: inner.height))
        return (s, CGSize(width: (dashboardDesign.width * s).rounded(), height: (dashboardDesign.height * s).rounded()))
    }

    /// Sidebar body width: 400 pt, but never more than 45 % of a small screen.
    public static func sidebarWidth(inner: CGRect) -> Double {
        max(260, min(sidebarDesignWidth, (inner.width * 0.45).rounded()))
    }

    /// The popout window: attached to the left band, vertically centred on `anchorMidY` and kept
    /// inside `inner`. `size` includes the two fillets (they run along the edge).
    public static func popoutFrame(size: CGSize, anchorMidY: Double, inner: CGRect) -> CGRect {
        let h = min(size.height, inner.height)
        let y = min(max(anchorMidY - h / 2, inner.minY), inner.maxY - h)
        return CGRect(x: inner.minX, y: y.rounded(), width: size.width, height: h)
    }

    /// The wallpaper strip: bottom-centre, as wide as fits.
    public static func wallpaperBody(inner: CGRect) -> CGSize {
        CGSize(width: min(wallpaperMaxWidth, max(320, inner.width - 48)), height: min(wallpaperStripHeight, max(120, inner.height - 24)))
    }
}
