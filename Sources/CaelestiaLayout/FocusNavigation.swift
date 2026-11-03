import Foundation
import CoreGraphics
import CaelestiaCore

/// Directional focus (Hyprland `movefocus l/r/u/d`) as pure geometry.
public enum FocusNavigation {
    /// The window next to `window` in `direction` among `placements` (hidden placements and the
    /// source itself are ignored).
    ///
    /// Candidates are windows whose frame lies in that direction (for `.right`:
    /// `other.minX >= source.maxX − 1`). Those overlapping the source's projection on the
    /// perpendicular axis are preferred; then the closest edge distance wins; ties go to the
    /// smallest perpendicular centre distance, then to the most recently focused window
    /// (`focusHistory`, most recent first), then to the top-most/left-most one.
    public static func neighbor(
        of window: WindowID, direction: Direction, placements: [Placement], focusHistory: [WindowID] = []
    ) -> WindowID? {
        guard let source = placements.first(where: { $0.window == window && !$0.hidden }) else { return nil }
        let candidates = placements.filter { !$0.hidden && $0.window != window }.map { ($0.window, $0.frame) }
        return neighbor(from: source.frame, direction: direction, candidates: candidates, focusHistory: focusHistory)
    }

    /// Same rule on raw rects.
    public static func neighbor(
        from source: CGRect, direction: Direction, candidates: [(id: WindowID, rect: CGRect)], focusHistory: [WindowID] = []
    ) -> WindowID? {
        var best: (key: SortKey, id: WindowID)?
        for (id, rect) in candidates {
            guard let key = SortKey(source: source, candidate: rect, direction: direction, id: id, focusHistory: focusHistory) else {
                continue
            }
            if best == nil || key < best!.key {
                best = (key, id)
            }
        }
        return best?.id
    }

    private struct SortKey: Comparable {
        var notOverlapping: Int
        var distance: Double
        var centerDistance: Double
        var historyIndex: Int
        var minY: Double
        var minX: Double
        var id: WindowID

        init?(source s: CGRect, candidate r: CGRect, direction: Direction, id: WindowID, focusHistory: [WindowID]) {
            let ahead: Bool
            let distance: Double
            let overlap: Double
            let centerDistance: Double
            switch direction {
            case .right:
                ahead = r.minX >= s.maxX - 1
                distance = r.minX - s.maxX
                overlap = min(s.maxY, r.maxY) - max(s.minY, r.minY)
                centerDistance = abs(r.midY - s.midY)
            case .left:
                ahead = r.maxX <= s.minX + 1
                distance = s.minX - r.maxX
                overlap = min(s.maxY, r.maxY) - max(s.minY, r.minY)
                centerDistance = abs(r.midY - s.midY)
            case .down:
                ahead = r.minY >= s.maxY - 1
                distance = r.minY - s.maxY
                overlap = min(s.maxX, r.maxX) - max(s.minX, r.minX)
                centerDistance = abs(r.midX - s.midX)
            case .up:
                ahead = r.maxY <= s.minY + 1
                distance = s.minY - r.maxY
                overlap = min(s.maxX, r.maxX) - max(s.minX, r.minX)
                centerDistance = abs(r.midX - s.midX)
            }
            guard ahead else { return nil }
            notOverlapping = overlap > 0 ? 0 : 1
            // Quantise to whole points so equal gaps compare equal despite float noise.
            self.distance = max(0, distance).rounded()
            self.centerDistance = centerDistance.rounded()
            historyIndex = focusHistory.firstIndex(of: id) ?? Int.max
            minY = r.minY
            minX = r.minX
            self.id = id
        }

        static func < (a: SortKey, b: SortKey) -> Bool {
            if a.notOverlapping != b.notOverlapping { return a.notOverlapping < b.notOverlapping }
            if a.distance != b.distance { return a.distance < b.distance }
            if a.centerDistance != b.centerDistance { return a.centerDistance < b.centerDistance }
            if a.historyIndex != b.historyIndex { return a.historyIndex < b.historyIndex }
            if a.minY != b.minY { return a.minY < b.minY }
            if a.minX != b.minX { return a.minX < b.minX }
            return a.id < b.id
        }
    }
}
