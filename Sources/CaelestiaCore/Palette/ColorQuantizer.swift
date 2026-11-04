import Foundation

/// A dominant colour and how many pixels fell in its cluster.
public struct QuantizedColor: Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var population: Int
}

/// Wu's colour quantizer (5 bits per channel histogram, variance-minimising box splits): the same
/// algorithm Material's `QuantizerWu` uses. Deterministic for a given pixel sequence.
public enum ColorQuantizer {
    private static let bits = 5
    private static let side = 33
    private static let total = 33 * 33 * 33

    private struct Box {
        var r0 = 0, r1 = 0, g0 = 0, g1 = 0, b0 = 0, b1 = 0, vol = 0
    }

    private enum Axis { case red, green, blue }

    private struct Moments {
        var weights = [Int](repeating: 0, count: ColorQuantizer.total)
        var mr = [Int](repeating: 0, count: ColorQuantizer.total)
        var mg = [Int](repeating: 0, count: ColorQuantizer.total)
        var mb = [Int](repeating: 0, count: ColorQuantizer.total)
        var m2 = [Double](repeating: 0, count: ColorQuantizer.total)
    }

    @inline(__always) private static func idx(_ r: Int, _ g: Int, _ b: Int) -> Int { (r * side + g) * side + b }

    /// `rgba` is tightly packed RGBA8 (4 bytes per pixel); pixels with alpha < 255 are skipped.
    public static func quantize(rgba: [UInt8], maxColors: Int = 128) -> [QuantizedColor] {
        guard maxColors > 0, rgba.count >= 4 else { return [] }
        var m = Moments()
        var any = false
        var i = 0
        while i + 3 < rgba.count {
            defer { i += 4 }
            guard rgba[i + 3] == 255 else { continue }
            any = true
            let r = Int(rgba[i]), g = Int(rgba[i + 1]), b = Int(rgba[i + 2])
            let k = idx((r >> 3) + 1, (g >> 3) + 1, (b >> 3) + 1)
            m.weights[k] += 1
            m.mr[k] += r
            m.mg[k] += g
            m.mb[k] += b
            m.m2[k] += Double(r * r + g * g + b * b)
        }
        guard any else { return [] }
        cumulate(&m)
        let boxes = split(m, count: maxColors)
        var out: [QuantizedColor] = []
        for box in boxes {
            let w = volume(box, m.weights)
            guard w > 0 else { continue }
            out.append(QuantizedColor(
                r: UInt8(min(255, volume(box, m.mr) / w)), g: UInt8(min(255, volume(box, m.mg) / w)),
                b: UInt8(min(255, volume(box, m.mb) / w)), population: w))
        }
        return out
    }

    private static func cumulate(_ m: inout Moments) {
        for r in 1..<side {
            var area = [Int](repeating: 0, count: side)
            var areaR = area, areaG = area, areaB = area
            var area2 = [Double](repeating: 0, count: side)
            for g in 1..<side {
                var line = 0, lineR = 0, lineG = 0, lineB = 0
                var line2 = 0.0
                for b in 1..<side {
                    let k = idx(r, g, b)
                    line += m.weights[k]
                    lineR += m.mr[k]
                    lineG += m.mg[k]
                    lineB += m.mb[k]
                    line2 += m.m2[k]
                    area[b] += line
                    areaR[b] += lineR
                    areaG[b] += lineG
                    areaB[b] += lineB
                    area2[b] += line2
                    let p = idx(r - 1, g, b)
                    m.weights[k] = m.weights[p] + area[b]
                    m.mr[k] = m.mr[p] + areaR[b]
                    m.mg[k] = m.mg[p] + areaG[b]
                    m.mb[k] = m.mb[p] + areaB[b]
                    m.m2[k] = m.m2[p] + area2[b]
                }
            }
        }
    }

    private static func volume(_ c: Box, _ m: [Int]) -> Int {
        m[idx(c.r1, c.g1, c.b1)] - m[idx(c.r1, c.g1, c.b0)] - m[idx(c.r1, c.g0, c.b1)] + m[idx(c.r1, c.g0, c.b0)]
            - m[idx(c.r0, c.g1, c.b1)] + m[idx(c.r0, c.g1, c.b0)] + m[idx(c.r0, c.g0, c.b1)] - m[idx(c.r0, c.g0, c.b0)]
    }

    private static func bottom(_ c: Box, _ axis: Axis, _ m: [Int]) -> Int {
        switch axis {
        case .red: return -m[idx(c.r0, c.g1, c.b1)] + m[idx(c.r0, c.g1, c.b0)] + m[idx(c.r0, c.g0, c.b1)] - m[idx(c.r0, c.g0, c.b0)]
        case .green: return -m[idx(c.r1, c.g0, c.b1)] + m[idx(c.r1, c.g0, c.b0)] + m[idx(c.r0, c.g0, c.b1)] - m[idx(c.r0, c.g0, c.b0)]
        case .blue: return -m[idx(c.r1, c.g1, c.b0)] + m[idx(c.r1, c.g0, c.b0)] + m[idx(c.r0, c.g1, c.b0)] - m[idx(c.r0, c.g0, c.b0)]
        }
    }

    private static func top(_ c: Box, _ axis: Axis, _ p: Int, _ m: [Int]) -> Int {
        switch axis {
        case .red: return m[idx(p, c.g1, c.b1)] - m[idx(p, c.g1, c.b0)] - m[idx(p, c.g0, c.b1)] + m[idx(p, c.g0, c.b0)]
        case .green: return m[idx(c.r1, p, c.b1)] - m[idx(c.r1, p, c.b0)] - m[idx(c.r0, p, c.b1)] + m[idx(c.r0, p, c.b0)]
        case .blue: return m[idx(c.r1, c.g1, p)] - m[idx(c.r1, c.g0, p)] - m[idx(c.r0, c.g1, p)] + m[idx(c.r0, c.g0, p)]
        }
    }

    private static func variance(_ c: Box, _ m: Moments) -> Double {
        let dr = Double(volume(c, m.mr)), dg = Double(volume(c, m.mg)), db = Double(volume(c, m.mb))
        let xx = m.m2[idx(c.r1, c.g1, c.b1)] - m.m2[idx(c.r1, c.g1, c.b0)] - m.m2[idx(c.r1, c.g0, c.b1)] + m.m2[idx(c.r1, c.g0, c.b0)]
            - m.m2[idx(c.r0, c.g1, c.b1)] + m.m2[idx(c.r0, c.g1, c.b0)] + m.m2[idx(c.r0, c.g0, c.b1)] - m.m2[idx(c.r0, c.g0, c.b0)]
        let hyp = dr * dr + dg * dg + db * db
        let vol = Double(volume(c, m.weights))
        return vol == 0 ? 0 : xx - hyp / vol
    }

    private static func maximize(
        _ c: Box, _ axis: Axis, _ first: Int, _ last: Int, _ m: Moments, whole: (Int, Int, Int, Int)
    ) -> (max: Double, cut: Int) {
        let bR = bottom(c, axis, m.mr), bG = bottom(c, axis, m.mg), bB = bottom(c, axis, m.mb), bW = bottom(c, axis, m.weights)
        var best = 0.0
        var cut = -1
        guard first < last else { return (0, -1) }
        for i in first..<last {
            var hR = bR + top(c, axis, i, m.mr), hG = bG + top(c, axis, i, m.mg)
            var hB = bB + top(c, axis, i, m.mb), hW = bW + top(c, axis, i, m.weights)
            if hW == 0 { continue }
            var t = (Double(hR * hR) + Double(hG * hG) + Double(hB * hB)) / Double(hW)
            hR = whole.0 - hR; hG = whole.1 - hG; hB = whole.2 - hB; hW = whole.3 - hW
            if hW == 0 { continue }
            t += (Double(hR * hR) + Double(hG * hG) + Double(hB * hB)) / Double(hW)
            if t > best { best = t; cut = i }
        }
        return (best, cut)
    }

    private static func cut(_ one: inout Box, _ two: inout Box, _ m: Moments) -> Bool {
        let whole = (volume(one, m.mr), volume(one, m.mg), volume(one, m.mb), volume(one, m.weights))
        let r = maximize(one, .red, one.r0 + 1, one.r1, m, whole: whole)
        let g = maximize(one, .green, one.g0 + 1, one.g1, m, whole: whole)
        let b = maximize(one, .blue, one.b0 + 1, one.b1, m, whole: whole)
        let axis: Axis
        if r.max >= g.max && r.max >= b.max {
            if r.cut < 0 { return false }
            axis = .red
        } else if g.max >= r.max && g.max >= b.max {
            axis = .green
        } else {
            axis = .blue
        }
        two = one
        switch axis {
        case .red: one.r1 = r.cut; two.r0 = r.cut
        case .green: one.g1 = g.cut; two.g0 = g.cut
        case .blue: one.b1 = b.cut; two.b0 = b.cut
        }
        one.vol = (one.r1 - one.r0) * (one.g1 - one.g0) * (one.b1 - one.b0)
        two.vol = (two.r1 - two.r0) * (two.g1 - two.g0) * (two.b1 - two.b0)
        return true
    }

    private static func split(_ m: Moments, count: Int) -> [Box] {
        var boxes = [Box](repeating: Box(), count: count)
        var variances = [Double](repeating: 0, count: count)
        boxes[0] = Box(r0: 0, r1: side - 1, g0: 0, g1: side - 1, b0: 0, b1: side - 1, vol: 0)
        var next = 0
        var generated = 1
        var i = 1
        while i < count {
            var one = boxes[next], two = Box()
            let didCut = cut(&one, &two, m)
            if didCut {
                boxes[next] = one
                boxes[i] = two
                variances[next] = one.vol > 1 ? variance(one, m) : 0
                variances[i] = two.vol > 1 ? variance(two, m) : 0
            } else {
                variances[next] = 0
            }
            let upper = didCut ? i : i - 1
            next = 0
            var best = variances[0]
            if upper >= 1 {
                for j in 1...upper where variances[j] > best {
                    best = variances[j]
                    next = j
                }
            }
            if didCut { generated = i + 1; i += 1 }
            if best <= 0 { break }
        }
        return Array(boxes.prefix(generated))
    }
}

/// Picks the colour a scheme should be built from (Material's `Score`): colours that are both
/// common (in their hue neighbourhood) and chromatic score highest; grey images yield no source.
public enum SourceColorScorer {
    public static let targetChroma = 48.0
    public static let cutoffChroma = 5.0
    public static let cutoffExcitedProportion = 0.01

    public static func rank(_ colors: [QuantizedColor], desired: Int = 4) -> [RGBA] {
        struct Entry { var color: RGBA; var hct: Hct; var score: Double }
        var huePopulation = [Double](repeating: 0, count: 360)
        var sum = 0.0
        var hcts: [(QuantizedColor, Hct)] = []
        for c in colors {
            let hct = Hct(r: c.r, g: c.g, b: c.b)
            hcts.append((c, hct))
            huePopulation[Int(hct.hue.rounded(.down)) % 360] += Double(c.population)
            sum += Double(c.population)
        }
        guard sum > 0 else { return [] }
        var excited = [Double](repeating: 0, count: 360)
        for hue in 0..<360 {
            let proportion = huePopulation[hue] / sum
            for i in (hue - 14)..<(hue + 16) { excited[((i % 360) + 360) % 360] += proportion }
        }
        var scored: [Entry] = []
        for (c, hct) in hcts {
            let hue = Int(hct.hue.rounded()) % 360
            let proportion = excited[hue]
            if hct.chroma < cutoffChroma || proportion <= cutoffExcitedProportion { continue }
            let proportionScore = proportion * 100 * 0.7
            let weight = hct.chroma < targetChroma ? 0.1 : 0.3
            let chromaScore = (hct.chroma - targetChroma) * weight
            scored.append(Entry(color: RGBA(r: c.r, g: c.g, b: c.b), hct: hct, score: proportionScore + chromaScore))
        }
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.hct.hue != $1.hct.hue { return $0.hct.hue < $1.hct.hue }
            return $0.color.hex < $1.color.hex
        }
        var chosen: [Entry] = []
        for difference in stride(from: 90, through: 15, by: -1) {
            chosen.removeAll()
            for e in scored {
                if !chosen.contains(where: { ColorMath.differenceDegrees(e.hct.hue, $0.hct.hue) < Double(difference) }) {
                    chosen.append(e)
                }
                if chosen.count >= desired { break }
            }
            if !chosen.isEmpty { break }
        }
        return chosen.map(\.color)
    }
}
