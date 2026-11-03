import CoreGraphics
import Foundation

/// Remembers the frames the WM asked windows to take so that the AX move/resize notifications
/// caused by our own `setFrame` calls can be recognised (spec 4.7: match within 2 pt for 250 ms).
/// Pure value type; `WindowDiscovery` owns one.
public struct FrameEchoFilter: Equatable, Sendable {
    public struct Expectation: Equatable, Sendable {
        public var frame: CGRect
        public var deadline: Date
        public init(frame: CGRect, deadline: Date) {
            self.frame = frame
            self.deadline = deadline
        }
    }

    /// Maximum per-component difference for a frame to count as an echo (points).
    public var tolerance: Double
    /// Default lifetime of an expectation when the caller gives none.
    public var lifetime: TimeInterval

    private var expectations: [CGWindowID: [Expectation]] = [:]

    public init(tolerance: Double = 2, lifetime: TimeInterval = 0.25) {
        self.tolerance = tolerance
        self.lifetime = lifetime
    }

    /// Registers `frame` as expected for `id` until `deadline`.
    public mutating func expect(_ id: CGWindowID, frame: CGRect, until deadline: Date) {
        expectations[id, default: []].append(Expectation(frame: frame, deadline: deadline))
    }

    /// Registers `frame` as expected for `id` for `lifetime` seconds from `now`.
    public mutating func expect(_ id: CGWindowID, frame: CGRect, now: Date = Date()) {
        expect(id, frame: frame, until: now.addingTimeInterval(lifetime))
    }

    /// True when `frame` matches a live expectation for `id`. Expired expectations are dropped;
    /// matching ones are kept until they expire because one write produces several notifications.
    public mutating func isEcho(_ id: CGWindowID, frame: CGRect, now: Date = Date()) -> Bool {
        guard var list = expectations[id] else { return false }
        list.removeAll { $0.deadline < now }
        if list.isEmpty {
            expectations[id] = nil
            return false
        }
        expectations[id] = list
        return list.contains { $0.frame.approximatelyEquals(frame, tolerance: tolerance) }
    }

    /// Drops every expired expectation.
    public mutating func prune(now: Date = Date()) {
        for (id, list) in expectations {
            let live = list.filter { $0.deadline >= now }
            expectations[id] = live.isEmpty ? nil : live
        }
    }

    /// Forgets everything about `id` (window destroyed).
    public mutating func forget(_ id: CGWindowID) {
        expectations[id] = nil
    }

    public func hasExpectations(for id: CGWindowID, now: Date = Date()) -> Bool {
        expectations[id]?.contains { $0.deadline >= now } ?? false
    }

    public var isEmpty: Bool { expectations.isEmpty }
}
