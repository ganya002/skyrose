import CoreGraphics
import Foundation

/// Which displays the focused app is covering (`bar.hideOverFullscreen`): the bar and the frame
/// step aside there so a game's own buttons get the clicks. Pure; the controller feeds it the
/// focused app's on-screen windows.
public enum FullscreenCover {
    public struct Display: Equatable {
        public var id: String
        /// Full frame, top-left space.
        public var frame: CGRect
        /// The notch strip native fullscreen leaves black (0 without a notch).
        public var notchInset: CGFloat
        public init(id: String, frame: CGRect, notchInset: CGFloat = 0) {
            self.id = id
            self.frame = frame
            self.notchInset = notchInset
        }
    }

    /// Smaller windows (tooltips, splash corners) never count.
    static let minSide: CGFloat = 100

    /// - Parameters:
    ///   - windows: the focused app's on-screen layer-0 windows, front to back (top-left space).
    ///   - backdrops: its on-screen windows below layer 0 (native fullscreen puts a black one
    ///     behind the window on a notched display).
    ///   - isGame: the focused app is tagged `game` by the rules.
    /// - Returns: each display whose front window of the app covers it (native or borderless
    ///   fullscreen), plus, for a game, the display under its front window even when it is
    ///   windowed. A windowed window of the app in front of its fullscreen one brings the bar back.
    public static func covered(displays: [Display], windows: [CGRect], backdrops: [CGRect] = [], isGame: Bool) -> Set<String> {
        let windows = windows.filter { $0.width >= minSide && $0.height >= minSide }
        var out = Set<String>()
        for d in displays {
            guard let front = windows.first(where: { display(of: $0, in: displays) == d.id }) else { continue }
            if covers(front, d.frame) {
                out.insert(d.id)
            } else if d.notchInset > 0, backdrops.contains(where: { covers($0, d.frame) }) {
                // Native fullscreen on a notched display: the window starts below the notch.
                var below = d.frame
                below.origin.y += d.notchInset
                below.size.height -= d.notchInset
                if covers(front, below) { out.insert(d.id) }
            }
        }
        if isGame, let front = windows.first, let d = display(of: front, in: displays) {
            out.insert(d)
        }
        return out
    }

    /// The window spans the whole rectangle (1 pt slack).
    static func covers(_ w: CGRect, _ d: CGRect) -> Bool {
        w.minX <= d.minX + 1 && w.minY <= d.minY + 1 && w.maxX >= d.maxX - 1 && w.maxY >= d.maxY - 1
    }

    /// The display holding most of the window.
    static func display(of w: CGRect, in displays: [Display]) -> String? {
        let best = displays.map { d -> (String, CGFloat) in
            let i = d.frame.intersection(w)
            return (d.id, i.isNull ? 0 : i.width * i.height)
        }.max { $0.1 < $1.1 }
        guard let best, best.1 > 0 else { return nil }
        return best.0
    }
}
