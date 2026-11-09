import CoreGraphics
import Foundation

/// One layout move, played on the real window. Each sample is only a frame: no opacity, blur,
/// tint or scale. A still scaled to a new size is what fades and stretches.
///
/// The clock is `animations.windowDurationMs` (default 150) on Hyprland's default ease-out.
/// It does not grow with distance. A mouse drag is `direct`: the sample is the cursor frame.
///
/// Size is committed on the first sample and stays there. macOS paints a size change by scaling
/// the old buffer, and a step bigger than about 2 pt stays visibly scaled until the app paints
/// (measured on this Mac). Walking the size 2 pt at a time made a full-width retile take seconds.
/// Position eases for the whole budget; the size jumps once, then only the origin moves, so the
/// buffer is not scaled on every refresh. 0 ms snaps.
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
        /// Mouse-drag: the frame is `to` itself, updated in place, with no ease and no catch-up.
        public var direct: Bool
    }

    public struct Sample: Equatable, Sendable {
        public var id: UInt32
        public var frame: CGRect
        public var finished: Bool
        public var snapped: Bool
    }

    public init(spec: AnimationSpec = .liveRetile(milliseconds: 150)) {
        self.spec = spec
    }

    public func contains(_ id: UInt32) -> Bool { tracks[id] != nil }
    public var isEmpty: Bool { tracks.isEmpty }

    public func startedAt(_ id: UInt32) -> TimeInterval? { tracks[id]?.sampler.startTime }

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
            if track.snapped || !track.sampler.spec.enabled || track.sampler.spec.durationMs <= 0 {
                return Sample(id: id, frame: track.to, finished: true, snapped: true)
            }
            let done = track.sampler.isDone(at: now)
            let t = done ? 1.0 : track.sampler.value(at: now)
            let origin = Interpolation.lerp(track.from.origin, track.to.origin, t)
            let posed = CGRect(origin: origin, size: track.to.size)
            let arrived = done || posed.approximatelyEquals(track.to, tolerance: 0.5)
            return Sample(id: id, frame: arrived ? track.to : posed, finished: arrived, snapped: false)
        }
    }

    /// What the app actually showed after we wrote `requested`. Returns true once the window
    /// should jump to its final frame and stop being sampled.
    @discardableResult
    public mutating func noteReadBack(_ id: UInt32, requested: CGRect, actual: CGRect, tolerance: Double = 2) -> Bool {
        guard var track = tracks[id], !track.snapped, !track.direct else { return tracks[id]?.snapped == true }
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
