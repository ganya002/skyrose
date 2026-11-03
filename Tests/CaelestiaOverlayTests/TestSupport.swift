import CaelestiaCore
import CoreGraphics
import Foundation

@testable import CaelestiaOverlay

/// Deterministic xorshift generator for the randomized R2 test.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Records everything the controller does to a surface.
@MainActor
final class FakeSurface: BorderSurface {
    nonisolated(unsafe) static var counter = 1000
    let windowNumber: Int
    private(set) var renders: [(sample: BorderSample, target: BorderTarget)] = []
    private(set) var orderedAbove: [CGWindowID] = []
    private(set) var closeCount = 0
    /// Renders that happened after `close()`; must stay 0.
    private(set) var rendersAfterClose = 0

    init() {
        FakeSurface.counter += 1
        windowNumber = FakeSurface.counter
    }

    func render(_ sample: BorderSample, target: BorderTarget, style: OverlayStyle) {
        if closeCount > 0 { rendersAfterClose += 1 }
        renders.append((sample, target))
    }
    func order(above id: CGWindowID) { orderedAbove.append(id) }
    func close() { closeCount += 1 }
}

final class TestClock: @unchecked Sendable {
    var now: TimeInterval = 0
}

func border(_ id: CGWindowID, _ frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100), active: Bool = false,
            appear: Appear = .popIn, motion: Motion = .animate, group: GroupBar? = nil) -> BorderTarget {
    BorderTarget(id: id, frame: frame, isActive: active, appear: appear, motion: motion, group: group)
}
