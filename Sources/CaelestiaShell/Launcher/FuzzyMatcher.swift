import Foundation

/// fzf-style fuzzy scoring (v1, greedy forward + backward tightening): every query character must
/// appear in order; consecutive runs, word starts, camelCase humps and a prefix match score
/// higher, gaps cost. Case-insensitive, diacritic-insensitive. Pure.
public enum FuzzyMatcher {
    public static let scoreMatch = 16
    public static let bonusBoundary = 10
    public static let bonusConsecutive = 8
    public static let bonusFirstChar = 12
    public static let bonusPrefix = 24
    public static let penaltyGapStart = 3
    public static let penaltyGapExtension = 1

    public struct Match: Equatable, Sendable {
        public var score: Int
        /// Indices (in Characters) of the matched characters in the candidate.
        public var positions: [Int]
    }

    static func fold(_ s: String) -> [Character] {
        Array(s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil))
    }

    /// nil when `query` is not a subsequence of `candidate`. An empty query matches with score 0.
    public static func match(_ query: String, in candidate: String) -> Match? {
        let q = fold(query.trimmingCharacters(in: .whitespaces)).filter { $0 != " " }
        guard !q.isEmpty else { return Match(score: 0, positions: []) }
        let original = Array(candidate)
        let c = fold(candidate)
        guard c.count >= q.count else { return nil }
        return matchFolded(q, c, original: c.count == original.count ? original : c)
    }

    private static func matchFolded(_ q: [Character], _ c: [Character], original: [Character]) -> Match? {
        // Forward pass: earliest end of a full subsequence match.
        var qi = 0
        var end = -1
        for (i, ch) in c.enumerated() where ch == q[qi] {
            qi += 1
            if qi == q.count { end = i; break }
        }
        guard end >= 0 else { return nil }
        // Backward pass from `end`: the tightest window ending there.
        qi = q.count - 1
        var start = end
        var i = end
        while i >= 0 {
            if c[i] == q[qi] {
                qi -= 1
                if qi < 0 { start = i; break }
            }
            i -= 1
        }
        // Score the window greedily left to right, preferring boundary positions.
        var positions: [Int] = []
        var score = 0
        qi = 0
        var lastPos = -2
        var inGap = false
        var idx = start
        while idx <= end, qi < q.count {
            if c[idx] == q[qi] {
                var s = scoreMatch
                let b = boundaryBonus(original, idx)
                s += b
                if lastPos == idx - 1 { s += bonusConsecutive + b / 2 }
                if qi == 0 { s += b > 0 ? bonusFirstChar : 0 }
                score += s
                positions.append(idx)
                lastPos = idx
                inGap = false
                qi += 1
            } else if !positions.isEmpty {
                score -= inGap ? penaltyGapExtension : penaltyGapStart
                inGap = true
            }
            idx += 1
        }
        guard qi == q.count else { return nil }
        if start == 0 { score += bonusPrefix }
        // Shorter candidates win ties (a little).
        score -= min(10, max(0, c.count - q.count) / 4)
        return Match(score: score, positions: positions)
    }

    static func boundaryBonus(_ s: [Character], _ i: Int) -> Int {
        guard i > 0 else { return bonusBoundary }
        let prev = s[i - 1], cur = s[i]
        if prev == " " || prev == "-" || prev == "_" || prev == "." || prev == "/" || prev == "(" { return bonusBoundary }
        if prev.isLowercase, cur.isUppercase { return bonusBoundary - 2 }
        if !prev.isNumber, cur.isNumber { return bonusBoundary / 2 }
        return 0
    }
}
