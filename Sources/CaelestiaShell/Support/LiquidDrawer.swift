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
        let still = shown || theme.reduceMotion
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
        let d = shown || theme.reduceMotion ? 0 : depth + 4
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
            .opacity(shown ? 1 : 0)
            .animation(shown ? theme.contentFadeIn : theme.drawerClose, value: shown)
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
