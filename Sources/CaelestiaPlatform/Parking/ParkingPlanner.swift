import CaelestiaCore
import CoreGraphics
import Foundation

/// Where to park windows of hidden workspaces and where to bring them back (spec 4.1, 4.4).
/// Pure; all rects in CG/AX top-left space.
public enum ParkingPlanner {
    /// Points of the parked window left on its display (macOS refuses to move a window fully
    /// off-screen, so one point stays visible in a corner, like AeroSpace).
    public static let visibleSliver: Double = 1

    /// Candidate corners, in preference order: bottom-right, bottom-left, top-right, top-left.
    public enum Corner: CaseIterable, Sendable {
        case bottomRight, bottomLeft, topRight, topLeft
    }

    /// The parked frame of a window of `size` on `display`: the first corner where the parked rect
    /// (minus its visible sliver) does not overlap any other display, so it never shows up on a
    /// neighbour. Falls back to bottom-right.
    public static func parkedFrame(size: CGSize, on display: CGRect, others: [CGRect]) -> CGRect {
        for corner in Corner.allCases {
            let r = rect(size: size, corner: corner, on: display)
            if !others.contains(where: { $0.intersects(r.insetBy(dx: visibleSliver, dy: visibleSliver)) }) { return r }
        }
        return rect(size: size, corner: .bottomRight, on: display)
    }

    static func rect(size: CGSize, corner: Corner, on d: CGRect) -> CGRect {
        let s = visibleSliver
        let origin: CGPoint
        switch corner {
        case .bottomRight: origin = CGPoint(x: d.maxX - s, y: d.maxY - s)
        case .bottomLeft: origin = CGPoint(x: d.minX - size.width + s, y: d.maxY - s)
        case .topRight: origin = CGPoint(x: d.maxX - s, y: d.minY - size.height + s)
        case .topLeft: origin = CGPoint(x: d.minX - size.width + s, y: d.minY - size.height + s)
        }
        return CGRect(origin: origin, size: size)
    }

    /// True when at most a sliver of `frame` is on any display: the window is parked (or lost).
    public static func isOffScreen(_ frame: CGRect, displays: [CGRect]) -> Bool {
        !displays.contains { d in
            let i = d.intersection(frame)
            return !i.isNull && i.width > visibleSliver * 4 && i.height > visibleSliver * 4
        }
    }

    /// A visible frame for a window being restored after a crash or uninstall (spec 10.10, R6):
    /// the remembered frame if most of it is on a display, else the same size centred in the
    /// usable area of the remembered display (or the primary one), shrunk to fit.
    public static func restoreFrame(remembered: CGRect, preferredDisplay: String?, displays: [DisplayInfo]) -> CGRect {
        let frames = displays.map(\.frame)
        if !remembered.isNull, !remembered.isEmpty,
           let host = frames.max(by: { overlapRatio(remembered, $0) < overlapRatio(remembered, $1) }),
           overlapRatio(remembered, host) >= 0.5
        {
            return remembered
        }
        let target = displays.first { $0.id == preferredDisplay } ?? displays.first { $0.isPrimary } ?? displays.first
        guard let target else { return remembered }
        let area = target.usableArea(reserved: .zero)
        let size = CGSize(
            width: min(remembered.isNull ? area.width * 0.6 : remembered.width, area.width),
            height: min(remembered.isNull ? area.height * 0.7 : remembered.height, area.height)
        )
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
            .integralPoints
    }

    static func overlapRatio(_ r: CGRect, _ d: CGRect) -> Double {
        let i = r.intersection(d)
        guard !i.isNull, r.width > 0, r.height > 0 else { return 0 }
        return (i.width * i.height) / (r.width * r.height)
    }
}
