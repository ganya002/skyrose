import Accelerate
import Foundation

/// The bar values of Caelestia's cava visualiser from raw system-output samples: an FFT per window,
/// `bars` log-spaced bands from `lowHz` to `highHz`, cava's auto-sensitivity (the loudest recent band
/// is 1) and its gravity fall-off (bars rise at once and fall smoothly). Values are 0...1.
public struct Spectrum: Sendable {
    public let bars: Int
    public var sampleRate: Double
    public let window: Int
    public let lowHz: Double
    public let highHz: Double
    /// Fraction of a bar kept per update while it falls (cava `gravity`).
    public var fall: Double = 0.82
    public private(set) var values: [Double]

    private var carry: [Float] = []
    private var peak: Double = 1e-6
    private let hann: [Float]
    private let log2n: vDSP_Length

    public init(bars: Int = 45, sampleRate: Double = 44100, window: Int = 2048, lowHz: Double = 50, highHz: Double = 12000) {
        self.bars = max(1, bars)
        self.sampleRate = sampleRate
        let n = 1 << Int(log2(Double(max(64, window))).rounded(.down))
        self.window = n
        self.lowHz = lowHz
        self.highHz = highHz
        values = Array(repeating: 0, count: max(1, bars))
        hann = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        log2n = vDSP_Length(log2(Double(n)))
    }

    /// Adds samples; returns true when `values` changed (one or more full windows were analysed).
    @discardableResult
    public mutating func feed(_ samples: [Float]) -> Bool {
        carry.append(contentsOf: samples)
        var changed = false
        while carry.count >= window {
            analyse(Array(carry.prefix(window)))
            carry.removeFirst(window / 2)  // 50 % overlap
            changed = true
        }
        return changed
    }

    /// Silence: bars fall back to 0 over a few updates.
    public mutating func decay() {
        values = values.map { $0 * fall < 0.005 ? 0 : $0 * fall }
    }

    private mutating func analyse(_ frame: [Float]) {
        let n = window
        let windowed = vDSP.multiply(frame, hann)
        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var magnitudes = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_destroy_fftsetup(setup)
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
            }
        }
        let binHz = sampleRate / Double(n)
        let top = min(highHz, sampleRate / 2)
        var raw = [Double](repeating: 0, count: bars)
        for b in 0..<bars {
            let f0 = lowHz * pow(top / lowHz, Double(b) / Double(bars))
            let f1 = lowHz * pow(top / lowHz, Double(b + 1) / Double(bars))
            let i0 = max(1, Int(f0 / binHz)), i1 = max(i0 + 1, min(n / 2, Int(f1 / binHz) + 1))
            var sum: Float = 0
            for i in i0..<i1 { sum += magnitudes[i] }
            // Mean energy, tilted up with frequency so treble is visible like cava's EQ.
            raw[b] = Double(sum / Float(i1 - i0)) * (1 + Double(b) / Double(bars) * 2)
        }
        let loudest = raw.max() ?? 0
        // Auto-sensitivity: follow a louder peak at once, forget a quiet one slowly.
        peak = loudest > peak ? loudest : max(1e-6, peak * 0.995)
        for b in 0..<bars {
            let v = loudest < 1e-4 ? 0 : min(1, raw[b] / peak)
            values[b] = v >= values[b] ? v : values[b] * fall + v * (1 - fall)
        }
    }
}
