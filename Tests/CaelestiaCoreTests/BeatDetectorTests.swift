import XCTest
@testable import CaelestiaCore

final class BeatDetectorTests: XCTestCase {
    /// A kick at 120 BPM under a steady, louder-than-silence mix: the case a full-band detector misses.
    func testBeatsAreFoundUnderAFullMix() {
        let rate = 44100.0
        let seconds = 8.0
        var samples = [Float](repeating: 0, count: Int(rate * seconds))
        var generator = SystemRandomNumberGenerator()
        for i in samples.indices {
            let t = Double(i) / rate
            let sinceKick = t.truncatingRemainder(dividingBy: 0.5)
            let kick = sin(2 * .pi * 70 * t) * exp(-sinceKick * 22) * 0.55
            let pad = sin(2 * .pi * 440 * t) * 0.18 + sin(2 * .pi * 660 * t) * 0.12
            let noise = Double.random(in: -0.12...0.12, using: &generator)
            samples[i] = Float(kick + pad + noise)
        }
        var detector = BeatDetector()
        var beats: [Double] = []
        // In the chunks a capture delivers.
        for start in stride(from: 0, to: samples.count, by: 1024) {
            beats += detector.feed(Array(samples[start..<min(start + 1024, samples.count)]))
        }
        XCTAssertEqual(beats.count, 16, accuracy: 1, "\(beats)")
        let settled = beats.dropFirst(2)
        for (a, b) in zip(settled, settled.dropFirst()) { XCTAssertEqual(b - a, 0.5, accuracy: 0.06) }
    }

    func testAQuietSongStillHasBeats() {
        var samples = [Float](repeating: 0, count: 44100 * 4)
        for i in samples.indices {
            let t = Double(i) / 44100
            samples[i] = Float(sin(2 * .pi * 70 * t) * exp(-t.truncatingRemainder(dividingBy: 0.5) * 22) * 0.02)
        }
        var detector = BeatDetector()
        XCTAssertGreaterThanOrEqual(detector.feed(samples).count, 6)
    }
}
