import CaelestiaCore
import CoreGraphics
import Foundation
import SwiftUI

/// Screen edge a drawer is attached to.
public enum ShellEdge: String, Sendable, Equatable, CaseIterable {
    case top, bottom, left, right
}

/// Caelestia drawers grow out of the screen frame: a rounded body whose two corners on the frame
/// side flare into concave fillets, so the drawer and the frame read as one shape.
///
/// Built in a canonical space (u along the edge, v towards the edge; the edge is at v = height),
/// then mapped onto the real edge. All paths are in a y-down space (SwiftUI / flipped layers).
public enum DrawerPath {
    /// - Parameters:
    ///   - rect: the whole shape, fillets included (they take `fillet` on both ends along the edge).
    ///   - radius: rounding of the body's two free corners.
    ///   - fillet: radius of the concave flares where the body meets the frame.
    public static func path(in rect: CGRect, edge: ShellEdge, radius: Double, fillet: Double) -> CGPath {
        let along = (edge == .top || edge == .bottom) ? rect.width : rect.height
        let depth = (edge == .top || edge == .bottom) ? rect.height : rect.width
        let f = max(0, min(fillet, along / 2, depth))
        let r = max(0, min(radius, (along - 2 * f) / 2, depth - f))
        func p(_ u: Double, _ v: Double) -> CGPoint {
            switch edge {
            case .bottom: return CGPoint(x: rect.minX + u, y: rect.minY + v)
            case .top: return CGPoint(x: rect.minX + u, y: rect.maxY - v)
            case .right: return CGPoint(x: rect.minX + v, y: rect.minY + u)
            case .left: return CGPoint(x: rect.maxX - v, y: rect.minY + u)
            }
        }
        let w = along, h = depth
        let path = CGMutablePath()
        path.move(to: p(0, h))
        if f > 0 { path.addArc(tangent1End: p(f, h), tangent2End: p(f, 0), radius: f) }
        if r > 0 {
            path.addArc(tangent1End: p(f, 0), tangent2End: p(w - f, 0), radius: r)
            path.addArc(tangent1End: p(w - f, 0), tangent2End: p(w - f, h), radius: r)
        } else {
            path.addLine(to: p(f, 0))
            path.addLine(to: p(w - f, 0))
        }
        if f > 0 { path.addArc(tangent1End: p(w - f, h), tangent2End: p(w, h), radius: f) }
        path.addLine(to: p(w, h))
        path.closeSubpath()
        return path
    }
}

/// SwiftUI wrapper of `DrawerPath`.
public struct DrawerShape: Shape {
    public var edge: ShellEdge
    public var radius: Double
    public var fillet: Double

    public init(edge: ShellEdge, radius: Double = 25, fillet: Double = 25) {
        self.edge = edge
        self.radius = radius
        self.fillet = fillet
    }

    public func path(in rect: CGRect) -> Path {
        Path(DrawerPath.path(in: rect, edge: edge, radius: radius, fillet: fillet))
    }
}

/// The screen frame band: the outer rect minus a rounded inner rect (even-odd fill).
public enum FramePath {
    /// Inner (window-side) rect of the frame for the given band thicknesses (y-down).
    public static func inner(of outer: CGRect, insets: Insets) -> CGRect {
        CGRect(
            x: outer.minX + insets.left, y: outer.minY + insets.top,
            width: max(0, outer.width - insets.left - insets.right),
            height: max(0, outer.height - insets.top - insets.bottom)
        )
    }

    public static func path(outer: CGRect, insets: Insets, radius: Double) -> CGPath {
        let path = CGMutablePath()
        path.addRect(outer)
        let i = inner(of: outer, insets: insets)
        let r = max(0, min(radius, i.width / 2, i.height / 2))
        path.addRoundedRect(in: i, cornerWidth: r, cornerHeight: r)
        return path
    }
}

/// Where the shell lays out on one display (AppKit bottom-left space, like NSWindow frames).
public struct DisplayLayout: Equatable, Sendable {
    /// The display frame minus the Dock when it is shown: what the screen frame goes around.
    public var area: CGRect
    public var thickness: Double
    public var barWidth: Double

    /// Height of the menu-bar / notch strip at the top that windows can never use. The frame
    /// covers it (the top band is `thickness + topExtra`), so no wallpaper strip shows above the
    /// frame on a notched Mac with an auto-hidden menu bar; a revealed menu bar draws above it.
    public var topExtra: Double

    public init(display: DisplayInfo, converter: CoordinateConverter, thickness: Double, barWidth: Double) {
        area = converter.toBottomLeft(display.frame.insetBy(display.dockInsets))
        topExtra = display.menuBarHeight
        self.thickness = thickness
        self.barWidth = barWidth
    }

    public init(area: CGRect, thickness: Double, barWidth: Double, topExtra: Double = 0) {
        self.area = area
        self.thickness = thickness
        self.barWidth = barWidth
        self.topExtra = topExtra
    }

    /// Band thicknesses with the bar `reveal`ed by 0...1 (the bar widens the left band).
    public func frameInsets(barReveal: Double) -> Insets {
        let left = thickness + (max(barWidth, thickness) - thickness) * min(1, max(0, barReveal))
        return Insets(top: thickness + topExtra, left: left, bottom: thickness, right: thickness)
    }

    /// The window-side rect inside the frame (AppKit space).
    public func inner(barReveal: Double) -> CGRect {
        let i = frameInsets(barReveal: barReveal)
        return CGRect(x: area.minX + i.left, y: area.minY + i.bottom,
                      width: area.width - i.left - i.right, height: area.height - i.top - i.bottom)
    }

    /// The bar window: the left strip below the menu-bar / notch strip.
    public var barFrame: CGRect {
        CGRect(x: area.minX, y: area.minY, width: max(barWidth, thickness), height: area.height - topExtra)
    }

    /// The hover strip that reveals an auto-hidden bar: the left band.
    public func barHotZone(contains p: CGPoint) -> Bool {
        p.x >= area.minX - 1 && p.x <= area.minX + max(2, thickness) && p.y >= area.minY && p.y <= area.maxY
    }

    /// A drawer of `size` (fillets included) attached to `edge`, centred along it.
    public func drawerFrame(size: CGSize, edge: ShellEdge, barReveal: Double) -> CGRect {
        let inner = inner(barReveal: barReveal)
        switch edge {
        case .bottom:
            return CGRect(x: (inner.midX - size.width / 2).rounded(), y: inner.minY, width: size.width, height: size.height)
        case .top:
            return CGRect(x: (inner.midX - size.width / 2).rounded(), y: inner.maxY - size.height, width: size.width, height: size.height)
        case .right:
            return CGRect(x: inner.maxX - size.width, y: (inner.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        case .left:
            return CGRect(x: inner.minX, y: (inner.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        }
    }
}
