import Foundation

/// Finds drum hits in a stream of PCM samples. It listens to the bass, where the kick is: a hit
/// is a window whose low-band energy jumps above its recent average, with a floor that follows
/// the track so a quiet song still has beats, and nothing inside the refractory gap.
public struct BeatDetector: Equatable, Sendable {
    public var sampleRate: Double
    public var window: Int
    /// Bass energy must be this many times the running average.
    public var multiplier: Double
    public var refractory: Double
    /// One-pole low-pass cutoff, in Hz.
    public var cutoff: Double

    private var carry: [Float] = []
    private var average: Double
    private var peak: Double = 0
    private var lowPass: Double = 0
    private var lastBeat: Double
    private var clock: Double = 0

    public init(sampleRate: Double = 44100, window: Int = 1024, multiplier: Double = 1.6, refractory: Double = 0.2, cutoff: Double = 150, average: Double = 0) {
        self.sampleRate = sampleRate
        self.window = max(64, window)
        self.multiplier = multiplier
        self.refractory = refractory
        self.cutoff = cutoff
        self.average = average
        self.lastBeat = -refractory
    }

    /// Beat times, in seconds from the first sample this detector has seen.
    public mutating func feed(_ samples: [Float]) -> [Double] {
        guard sampleRate > 0 else { return [] }
        carry.append(contentsOf: samples)
        var beats: [Double] = []
        let alpha = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
        var start = 0
        while carry.count - start >= window {
            var energy = 0.0
            for i in start..<(start + window) {
                lowPass += alpha * (Double(carry[i]) - lowPass)
                energy += lowPass * lowPass
            }
            energy /= Double(window)
            start += window
            let at = clock
            clock += Double(window) / sampleRate
            // Silence (and digital noise) is never a beat. The floor follows the loudest recent bass.
            peak = max(energy, peak * 0.995)
            let floor = max(1e-7, peak * 0.15)
            if energy > floor, energy > average * multiplier, at - lastBeat >= refractory {
                beats.append(at)
                lastBeat = at
            }
            average = average * 0.9 + energy * 0.1
        }
        carry.removeFirst(start)
        return beats
    }
}
