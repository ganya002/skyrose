import CoreGraphics
import Foundation

/// Where keyboard focus puts the pointer. `center` is the window's middle. `last` is the last
/// point the pointer occupied inside that window, or the middle when there isn't one.
public enum CursorWarpMode: String, Codable, Sendable, CaseIterable {
    case center
    case last
}

/// The decision to move the pointer when focus changes. Pure: the WM applies it with
/// `CGWarpMouseCursorPosition` after disconnecting the hardware mouse, so the warp is not a hover.
public enum CursorWarp {
    /// Where to put the pointer, or nil when it must stay put.
    ///
    /// Stays put when the feature is off, a button is down, a drag is in progress, the window is
    /// not on a display the user can see, or the pointer is already inside the window (a click or
    /// a hover caused the focus).
    public static func destination(
        frame: CGRect, mode: CursorWarpMode, lastInside: CGPoint?, cursor: CGPoint?,
        mouseDown: Bool, dragging: Bool, enabled: Bool, onVisibleDisplay: Bool
    ) -> CGPoint? {
        guard enabled, !mouseDown, !dragging, onVisibleDisplay else { return nil }
        guard frame.width > 1, frame.height > 1, !frame.isNull, !frame.isInfinite else { return nil }
        if let cursor, frame.contains(cursor) { return nil }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        switch mode {
        case .center:
            return centre
        case .last:
            if let lastInside, frame.insetBy(dx: 1, dy: 1).contains(lastInside) { return lastInside }
            return centre
        }
    }
}
