import Foundation

/// Finds drum hits in a stream of PCM samples. A hit is a window whose energy jumps above the
/// recent average, and not another hit inside the refractory gap.
public struct BeatDetector: Equatable, Sendable {
    public var sampleRate: Double
    public var window: Int
    /// Energy must be this many times the running average.
    public var multiplier: Double
    public var refractory: Double

    private var carry: [Float] = []
    private var average: Double
    private var lastBeat: Double
    private var clock: Double = 0

    public init(sampleRate: Double = 44100, window: Int = 1024, multiplier: Double = 2.2, refractory: Double = 0.2, average: Double = 0.002) {
        self.sampleRate = sampleRate
        self.window = max(64, window)
        self.multiplier = multiplier
        self.refractory = refractory
        self.average = average
        self.lastBeat = -refractory
    }

    /// Beat times, in seconds from the first sample this detector has seen.
    public mutating func feed(_ samples: [Float]) -> [Double] {
        guard sampleRate > 0 else { return [] }
        carry.append(contentsOf: samples)
        var beats: [Double] = []
        while carry.count >= window {
            let energy = carry.prefix(window).reduce(0.0) { $0 + Double($1 * $1) } / Double(window)
            let at = clock
            clock += Double(window) / sampleRate
            carry.removeFirst(window)
            if energy > 0.005, energy > average * multiplier, at - lastBeat >= refractory {
                beats.append(at)
                lastBeat = at
            }
            average = average * 0.85 + energy * 0.15
        }
        return beats
    }
}
