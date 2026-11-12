import XCTest
@testable import CaelestiaCore

final class SpectrumTests: XCTestCase {
    private func sine(_ hz: Double, count: Int, rate: Double = 44100) -> [Float] {
        (0..<count).map { Float(sin(2 * .pi * hz * Double($0) / rate)) * 0.5 }
    }

    func testSilenceStaysZero() {
        var s = Spectrum()
        XCTAssertTrue(s.feed([Float](repeating: 0, count: 4096)))
        XCTAssertEqual(s.values.max(), 0)
    }

    func testToneLightsItsBand() {
        var s = Spectrum(bars: 45)
        s.feed(sine(1000, count: 8192))
        let loudest = s.values.indices.max { s.values[$0] < s.values[$1] }!
        // The band that holds 1 kHz on the 50 Hz–12 kHz log scale.
        let expected = Int(log(1000.0 / 50) / log(12000.0 / 50) * 45)
        XCTAssertLessThanOrEqual(abs(loudest - expected), 1)
        XCTAssertEqual(s.values[loudest], 1, accuracy: 1e-9)
        XCTAssertLessThan(s.values[0], 0.2)
        XCTAssertLessThan(s.values[44], 0.2)
    }

    func testBarsFallAfterTheSoundStops() {
        var s = Spectrum()
        s.feed(sine(200, count: 8192))
        let before = s.values.max()!
        s.decay()
        XCTAssertLessThan(s.values.max()!, before)
        for _ in 0..<60 { s.decay() }
        XCTAssertEqual(s.values.max(), 0)
    }

    func testNeedsAFullWindow() {
        var s = Spectrum(window: 2048)
        XCTAssertFalse(s.feed([Float](repeating: 0.1, count: 2000)))
        XCTAssertTrue(s.feed([Float](repeating: 0.1, count: 100)))
    }
}
