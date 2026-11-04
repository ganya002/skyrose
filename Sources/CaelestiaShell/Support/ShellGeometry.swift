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

/// Radii of a rectangle's four corners, named in y-down terms (top = the screen's top edge).
public struct CornerRadii: Equatable, Sendable {
    public var topLeft, topRight, bottomRight, bottomLeft: Double

    public init(topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public static func uniform(_ r: Double) -> CornerRadii { CornerRadii(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }
    public static let zero = CornerRadii.uniform(0)
}

/// The screen frame band: the outer rect minus a rounded inner rect (even-odd fill). With
/// cutouts (a notch) the top band wraps each one: the band dips down around it by `thickness`,
/// with rounded corners where it leaves the band and below the cutout.
public enum FramePath {
    /// Rounding of the dip's two lower corners and of the two corners where it leaves the band.
    public static let cutoutCornerRadius: Double = 12
    public static let cutoutJoinRadius: Double = 8

    /// Inner (window-side) rect of the frame for the given band thicknesses (y-down).
    public static func inner(of outer: CGRect, insets: Insets) -> CGRect {
        CGRect(
            x: outer.minX + insets.left, y: outer.minY + insets.top,
            width: max(0, outer.width - insets.left - insets.right),
            height: max(0, outer.height - insets.top - insets.bottom)
        )
    }

    public static func path(outer: CGRect, insets: Insets, radius: Double) -> CGPath {
        path(outer: outer, insets: insets, radius: radius, cutouts: [], thickness: 0)
    }

    /// - Parameter cutouts: hardware cutouts in the same y-down space as `outer`.
    public static func path(outer: CGRect, insets: Insets, radius: Double, cutouts: [CGRect], thickness: Double) -> CGPath {
        path(outer: outer, insets: insets, outerRadii: .zero, innerRadii: .uniform(radius), cutouts: cutouts, thickness: thickness)
    }

    /// The band with its outer edge rounded by `outerRadii` (the display's physical corners; 0 =
    /// square) and its window-side corners by `innerRadii`.
    public static func path(outer: CGRect, insets: Insets, outerRadii: CornerRadii, innerRadii: CornerRadii,
                            cutouts: [CGRect], thickness: Double) -> CGPath {
        let path = CGMutablePath()
        if outerRadii == .zero {
            path.addRect(outer)
        } else {
            addRoundedPolygon([
                (CGPoint(x: outer.minX, y: outer.minY), outerRadii.topLeft),
                (CGPoint(x: outer.maxX, y: outer.minY), outerRadii.topRight),
                (CGPoint(x: outer.maxX, y: outer.maxY), outerRadii.bottomRight),
                (CGPoint(x: outer.minX, y: outer.maxY), outerRadii.bottomLeft),
            ], to: path)
        }
        let i = inner(of: outer, insets: insets)
        guard i.width > 0, i.height > 0 else { return path }
        func clamp(_ r: Double) -> Double { max(0, min(r, i.width / 2, i.height / 2)) }
        let rTL = clamp(innerRadii.topLeft), rTR = clamp(innerRadii.topRight)
        let rBR = clamp(innerRadii.bottomRight), rBL = clamp(innerRadii.bottomLeft)
        let dips = self.dips(cutouts: cutouts, inner: i, thickness: thickness)
        guard !dips.isEmpty else {
            if rTL == rTR, rTR == rBR, rBR == rBL {
                path.addRoundedRect(in: i, cornerWidth: rTL, cornerHeight: rTL)
            } else {
                addRoundedPolygon([
                    (CGPoint(x: i.minX, y: i.minY), rTL), (CGPoint(x: i.maxX, y: i.minY), rTR),
                    (CGPoint(x: i.maxX, y: i.maxY), rBR), (CGPoint(x: i.minX, y: i.maxY), rBL),
                ], to: path)
            }
            return path
        }
        // The hole as a polygon (clockwise in y-down space), every vertex with its own rounding.
        var v: [(CGPoint, Double)] = []
        var leftStart = CGPoint(x: i.minX, y: i.minY)
        var leftRadius = rTL
        if let first = dips.first, first.minX <= i.minX + 0.5 {
            leftStart = CGPoint(x: i.minX, y: first.maxY)
            leftRadius = min(rTL, cutoutCornerRadius)
        }
        v.append((leftStart, leftRadius))
        for d in dips {
            if d.minX > i.minX + 0.5 {
                v.append((CGPoint(x: d.minX, y: i.minY), cutoutJoinRadius))
                v.append((CGPoint(x: d.minX, y: d.maxY), cutoutCornerRadius))
            }
            if d.maxX < i.maxX - 0.5 {
                v.append((CGPoint(x: d.maxX, y: d.maxY), cutoutCornerRadius))
                v.append((CGPoint(x: d.maxX, y: i.minY), cutoutJoinRadius))
            }
        }
        if let last = dips.last, last.maxX >= i.maxX - 0.5 {
            v.append((CGPoint(x: i.maxX, y: last.maxY), min(rTR, cutoutCornerRadius)))
        } else {
            v.append((CGPoint(x: i.maxX, y: i.minY), rTR))
        }
        v.append((CGPoint(x: i.maxX, y: i.maxY), rBR))
        v.append((CGPoint(x: i.minX, y: i.maxY), rBL))
        addRoundedPolygon(v, to: path)
        return path
    }

    /// Where the band dips around the cutouts (y-down, inside `inner`): each cutout grown by
    /// `thickness` on its sides and bottom, clipped to `inner`, overlapping dips merged.
    public static func dips(cutouts: [CGRect], inner i: CGRect, thickness: Double) -> [CGRect] {
        var dips = cutouts.compactMap { c -> CGRect? in
            let bottom = c.maxY + thickness
            guard bottom > i.minY + 0.5, c.maxX > i.minX, c.minX < i.maxX else { return nil }
            let minX = max(i.minX, c.minX - thickness), maxX = min(i.maxX, c.maxX + thickness)
            return CGRect(x: minX, y: i.minY, width: maxX - minX, height: min(i.height, bottom - i.minY))
        }.sorted { $0.minX < $1.minX }
        var merged: [CGRect] = []
        for d in dips {
            if let last = merged.last, d.minX <= last.maxX + 2 * cutoutJoinRadius {
                merged[merged.count - 1] = CGRect(x: last.minX, y: i.minY, width: max(last.maxX, d.maxX) - last.minX,
                                                  height: max(last.height, d.height))
            } else {
                merged.append(d)
            }
        }
        dips = merged
        return dips
    }

    /// A closed polygon whose corners are rounded with `addArc(tangent1End:tangent2End:)`; each
    /// radius is clamped to half of both adjacent edges so neighbouring arcs never overlap.
    static func addRoundedPolygon(_ v: [(CGPoint, Double)], to path: CGMutablePath) {
        var pts: [(CGPoint, Double)] = []
        for p in v where pts.last.map({ hypot($0.0.x - p.0.x, $0.0.y - p.0.y) > 0.01 }) ?? true { pts.append(p) }
        if pts.count > 1, hypot(pts[0].0.x - pts[pts.count - 1].0.x, pts[0].0.y - pts[pts.count - 1].0.y) < 0.01 { pts.removeLast() }
        guard pts.count >= 3 else { return }
        let n = pts.count
        func len(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(b.x - a.x, b.y - a.y) }
        let start = CGPoint(x: (pts[n - 1].0.x + pts[0].0.x) / 2, y: (pts[n - 1].0.y + pts[0].0.y) / 2)
        path.move(to: start)
        for k in 0..<n {
            let prev = pts[(k + n - 1) % n].0, cur = pts[k].0, next = pts[(k + 1) % n].0
            let r = max(0, min(pts[k].1, len(prev, cur) / 2, len(cur, next) / 2))
            if r > 0 { path.addArc(tangent1End: cur, tangent2End: next, radius: r) } else { path.addLine(to: cur) }
        }
        path.closeSubpath()
    }
}

/// Where the shell lays out on one display (AppKit bottom-left space, like NSWindow frames).
public struct DisplayLayout: Equatable, Sendable {
    /// The display frame minus the Dock and a shown menu bar: what the screen frame goes around.
    public var area: CGRect
    public var thickness: Double
    public var barWidth: Double

    /// An extra plain band at the top (0 for displays built from `DisplayInfo`: a shown menu bar
    /// is outside `area` and a notch is wrapped through `cutouts`). Kept for explicit layouts.
    public var topExtra: Double
    /// Hardware cutouts (notch) in AppKit global space. The band wraps around each one.
    public var cutouts: [CGRect]
    /// The display's physical top corner radius (`frame.displayCornerRadius`), applied to the
    /// outer corners of `area` that are real display corners (`physicalCorners`).
    public var displayCornerRadius: Double
    /// The same for the bottom corners (`frame.displayBottomCornerRadius`).
    public var bottomCornerRadius: Double
    /// Which corners of `area` coincide with the display's own corners (not with a shown Dock or
    /// menu bar edge, where the band meets ordinary pixels).
    public var physicalCorners: PhysicalCorners

    public struct PhysicalCorners: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let topLeft = PhysicalCorners(rawValue: 1)
        public static let topRight = PhysicalCorners(rawValue: 2)
        public static let bottomRight = PhysicalCorners(rawValue: 4)
        public static let bottomLeft = PhysicalCorners(rawValue: 8)
        public static let all: PhysicalCorners = [.topLeft, .topRight, .bottomRight, .bottomLeft]
    }

    public init(display: DisplayInfo, converter: CoordinateConverter, thickness: Double, barWidth: Double, displayCornerRadius: Double = 0,
                bottomCornerRadius: Double? = nil) {
        var top = display.frame.insetBy(display.dockInsets)
        top.origin.y += display.shownMenuBarHeight
        top.size.height = max(0, top.height - display.shownMenuBarHeight)
        area = converter.toBottomLeft(top)
        topExtra = 0
        cutouts = display.topCutouts.map { converter.toBottomLeft($0) }
        self.thickness = thickness
        self.barWidth = barWidth
        self.displayCornerRadius = max(0, displayCornerRadius)
        self.bottomCornerRadius = max(0, bottomCornerRadius ?? displayCornerRadius)
        let f = display.frame
        let atTop = abs(top.minY - f.minY) < 0.5, atBottom = abs(top.maxY - f.maxY) < 0.5
        let atLeft = abs(top.minX - f.minX) < 0.5, atRight = abs(top.maxX - f.maxX) < 0.5
        var corners: PhysicalCorners = []
        if atTop, atLeft { corners.insert(.topLeft) }
        if atTop, atRight { corners.insert(.topRight) }
        if atBottom, atRight { corners.insert(.bottomRight) }
        if atBottom, atLeft { corners.insert(.bottomLeft) }
        physicalCorners = corners
    }

    public init(area: CGRect, thickness: Double, barWidth: Double, topExtra: Double = 0, cutouts: [CGRect] = [],
                displayCornerRadius: Double = 0, bottomCornerRadius: Double? = nil, physicalCorners: PhysicalCorners = .all) {
        self.area = area
        self.thickness = thickness
        self.barWidth = barWidth
        self.topExtra = topExtra
        self.cutouts = cutouts
        self.displayCornerRadius = max(0, displayCornerRadius)
        self.bottomCornerRadius = max(0, bottomCornerRadius ?? displayCornerRadius)
        self.physicalCorners = physicalCorners
    }

    /// Outer radii of the frame band: the display radii at physical corners, square elsewhere.
    public var outerRadii: CornerRadii {
        let t = displayCornerRadius, b = bottomCornerRadius
        return CornerRadii(
            topLeft: physicalCorners.contains(.topLeft) ? t : 0, topRight: physicalCorners.contains(.topRight) ? t : 0,
            bottomRight: physicalCorners.contains(.bottomRight) ? b : 0, bottomLeft: physicalCorners.contains(.bottomLeft) ? b : 0
        )
    }

    /// Window-side radii of the band. Where the outer corner is rounded the inner arc is
    /// concentric with it: outer radius − band thickness (0, a square inner corner, once the
    /// radius is no larger than the band), so the band keeps one width around the corner.
    /// `base` (the theme's frame rounding) where the outer corner is square.
    public func innerRadii(base: Double) -> CornerRadii {
        let o = outerRadii
        func r(_ outer: Double) -> Double { outer > 0 ? max(0, outer - thickness) : base }
        return CornerRadii(topLeft: r(o.topLeft), topRight: r(o.topRight), bottomRight: r(o.bottomRight), bottomLeft: r(o.bottomLeft))
    }

    /// Cutouts in the frame panel's own y-down space (origin at the area's top-left).
    public var localCutouts: [CGRect] {
        cutouts.map { CGRect(x: $0.minX - area.minX, y: area.maxY - $0.maxY, width: $0.width, height: $0.height) }
    }

    /// How far below the top band's inner edge something spanning `minX...maxX` must keep its
    /// content to clear the band's dip around a cutout (0 when no cutout is in that range).
    public func topClearance(minX: Double, maxX: Double) -> Double {
        let bandBottom = area.maxY - thickness - topExtra
        return cutouts.filter { $0.maxX > minX && $0.minX < maxX }
            .map { max(0, bandBottom - ($0.minY - thickness)) }
            .max() ?? 0
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

    /// The bar window: the left strip of the frame, below the top band's dip if a cutout
    /// reaches into the bar's column (never on current Macs: the notch is centred).
    public var barFrame: CGRect {
        let w = max(barWidth, thickness)
        let dip = topClearance(minX: area.minX, maxX: area.minX + w)
        let blocked = dip > 0 ? dip + thickness : 0
        return CGRect(x: area.minX, y: area.minY, width: w, height: max(0, area.height - topExtra - blocked))
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
