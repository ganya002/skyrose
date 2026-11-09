import CoreGraphics
import Foundation

/// One layout resize, played on the real window. The output of a tick is only a frame: there is
/// no opacity, blur, tint or scale. A still scaled to a new size is what fades and stretches.
///
/// The curve is the window-move animation (the 300 ms spring used for retile, Hyprland-style).
/// One track per window: a second target before the next tick replaces the first (coalesced).
/// Two read-backs that are not the frame we asked for snap that window to the final frame.
public struct LiveResizeSchedule: Equatable, Sendable {
    public static let missLimit = 2

    public var spec: AnimationSpec
    public private(set) var tracks: [UInt32: Track] = [:]

    public struct Track: Equatable, Sendable {
        public var from: CGRect
        public var to: CGRect
        public var sampler: FrameSampler
        public var missed: Int
        public var snapped: Bool
        /// Mouse-drag: the frame is `to` itself, updated in place, with no spring lag.
        public var direct: Bool
    }

    public struct Sample: Equatable, Sendable {
        public var id: UInt32
        public var frame: CGRect
        public var finished: Bool
        public var snapped: Bool
    }

    public init(spec: AnimationSpec = AnimationTable.gabbySpringy()[.windowsMove]) {
        self.spec = spec
    }

    public func contains(_ id: UInt32) -> Bool { tracks[id] != nil }
    public var isEmpty: Bool { tracks.isEmpty }

    /// `from` is where the window is now (the current sample, if one is in flight).
    /// `direct` follows `to` with no interpolation: a mouse-drag edge stays on the cursor.
    public mutating func retarget(_ id: UInt32, from: CGRect, to: CGRect, at now: TimeInterval, direct: Bool = false) {
        if direct, var track = tracks[id] {
            track.to = to
            track.direct = true
            tracks[id] = track
            return
        }
        tracks[id] = Track(
            from: from, to: to, sampler: FrameSampler(spec: spec, startTime: now), missed: 0, snapped: false, direct: direct
        )
    }

    public func samples(at now: TimeInterval) -> [Sample] {
        tracks.keys.sorted().compactMap { id in
            guard let track = tracks[id] else { return nil }
            if track.direct {
                return Sample(id: id, frame: track.to, finished: false, snapped: false)
            }
            if track.snapped {
                return Sample(id: id, frame: track.to, finished: true, snapped: true)
            }
            let done = track.sampler.isDone(at: now)
            let frame = done ? track.to : track.sampler.frame(from: track.from, to: track.to, at: now)
            return Sample(id: id, frame: frame, finished: done, snapped: false)
        }
    }

    /// What the app actually showed after we wrote `requested`. Returns true once the window
    /// should jump to its final frame and stop being sampled.
    @discardableResult
    public mutating func noteReadBack(_ id: UInt32, requested: CGRect, actual: CGRect, tolerance: Double = 2) -> Bool {
        guard var track = tracks[id], !track.snapped else { return tracks[id]?.snapped == true }
        if actual.isNull || !actual.approximatelyEquals(requested, tolerance: tolerance) {
            track.missed += 1
            if track.missed >= Self.missLimit { track.snapped = true }
        } else {
            track.missed = 0
        }
        tracks[id] = track
        return track.snapped
    }

    public mutating func remove(_ id: UInt32) { tracks[id] = nil }
}
