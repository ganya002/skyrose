import CaelestiaCore
import SwiftUI

/// Caelestia's drawers grow out of the screen frame like blobs. SkyRose's version, in two layers
/// driven by one `shown` flag:
///
/// - the **body** (the frosted drawer shape) scales out of its edge along the normal on a spring
///   that swings ~16 pt past full size and settles, while its **neck** along the edge starts at
///   84 % and widens on a slower, critically damped spring: the joint to the frame stretches,
///   then settles (drawers that span a whole edge, like the sidebar, have no neck: Caelestia's
///   is full height from its first frame). Closing shrinks it back into the frame (`drawerClose`) while the panel fades.
/// - the **content** rides the same spring as an offset, so it stays inside the body's far edge,
///   and fades in just after the body starts (it never shows outside the narrow neck).
///
/// The body is a layer-backed `FrostedView`, so only transforms animate (its path is not morphed
/// per frame). Reduce Motion: no scale, no offset; the panel cross-fades.
extension View {
    func liquidBody(edge: ShellEdge, shown: Bool, depth: Double, theme: ShellTheme, neck: Bool = true, neckAnchor: UnitPoint? = nil) -> some View {
        // On the liquid surface the frame's display link moves the whole drawer.
        let still = shown || theme.reduceMotion || theme.liquidSurface
        let n = still ? 1 : LiquidMotion.hiddenScale
        let a = still || !neck ? 1 : LiquidMotion.neckStart
        let vertical = edge == .top || edge == .bottom
        let anchor = LiquidAnchor.edge(edge)
        return self
            .scaleEffect(x: vertical ? 1 : n, y: vertical ? n : 1, anchor: anchor)
            .animation(shown ? theme.drawerSpring(depth: depth) : theme.drawerClose, value: shown)
            .scaleEffect(x: vertical ? a : 1, y: vertical ? 1 : a, anchor: neckAnchor ?? anchor)
            .animation(shown ? theme.neckSpring : theme.drawerClose, value: shown)
    }

    func liquidContent(edge: ShellEdge, shown: Bool, depth: Double, theme: ShellTheme) -> some View {
        let liquid = theme.liquidSurface
        let d = shown || theme.reduceMotion || liquid ? 0 : depth + 4
        let off: CGSize
        switch edge {
        case .top: off = CGSize(width: 0, height: -d)
        case .bottom: off = CGSize(width: 0, height: d)
        case .left: off = CGSize(width: -d, height: 0)
        case .right: off = CGSize(width: d, height: 0)
        }
        return self
            .offset(off)
            .animation(shown ? theme.drawerSpring(depth: depth) : theme.drawerClose, value: shown)
            .opacity(shown || liquid ? 1 : 0)
            .animation(shown ? theme.contentFadeIn : theme.drawerClose, value: shown)
    }
}

/// Reports a drawer's body rect (panel-local, y-down, fillets excluded) to its panel, which hands
/// it to the frame's `LiquidSurface`. Set by `ShellController.makeDrawerPanel`.
struct BlobReporterKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: (@MainActor (CGRect) -> Void)? = nil
}

extension EnvironmentValues {
    var blobReporter: (@MainActor (CGRect) -> Void)? {
        get { self[BlobReporterKey.self] }
        set { self[BlobReporterKey.self] = newValue }
    }
}

/// A drawer's background. On the liquid surface it draws nothing and reports where the body is
/// (the surface draws it, fillets and all); otherwise the frosted drawer shape on its spring.
struct DrawerBackground<S: Shape>: View {
    var shape: S
    var edge: ShellEdge
    /// Fillet margins inside the shape's frame that are not body.
    var inset: EdgeInsets
    var shown: Bool
    var depth: Double
    var neck = true
    var neckAnchor: UnitPoint?
    @Environment(\.shellTheme) var theme
    @Environment(\.blobReporter) var report

    var body: some View {
        if theme.liquidSurface {
            Color.clear
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                    report?(CGRect(x: r.minX + inset.leading, y: r.minY + inset.top,
                                   width: max(0, r.width - inset.leading - inset.trailing),
                                   height: max(0, r.height - inset.top - inset.bottom)))
                }
        } else {
            FrostedShape(shape: shape, theme: theme)
                .liquidBody(edge: edge, shown: shown, depth: depth, theme: theme, neck: neck, neckAnchor: neckAnchor)
        }
    }
}

extension DrawerBackground where S == DrawerShape {
    /// An edge drawer whose shape carries `fillet` on both ends along the edge.
    init(edge: ShellEdge, fillet: Double, radius: Double, shown: Bool, depth: Double, neck: Bool = true) {
        let along: EdgeInsets
        switch edge {
        case .top, .bottom: along = EdgeInsets(top: 0, leading: fillet, bottom: 0, trailing: fillet)
        case .left, .right: along = EdgeInsets(top: fillet, leading: 0, bottom: fillet, trailing: 0)
        }
        self.init(shape: DrawerShape(edge: edge, radius: radius, fillet: fillet), edge: edge, inset: along, shown: shown, depth: depth, neck: neck)
    }
}

enum LiquidAnchor {
    static func edge(_ e: ShellEdge) -> UnitPoint {
        switch e {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }
}
