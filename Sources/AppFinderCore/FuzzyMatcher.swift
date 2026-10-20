/// Fuzzy subsequence matching with an optimal alignment, in the manner of fzf's v2 algorithm.
///
/// Every query character must appear in the key, in order. Among all alignments the one with
/// the highest score wins: each matched character earns `match`, a character at a word start
/// earns `boundary` (twice that for the first query character), a run of consecutive characters
/// keeps the bonus of the character that started it (at least `consecutive`), and a gap costs
/// `gapStart` plus `gapExtension` for every further skipped character. Skipping characters before
/// the first match costs `leading` each, up to `leadingCap`, so that earlier matches win ties.
public enum FuzzyMatcher {
    public struct Match: Sendable, Equatable {
        public let score: Int
        /// Indices into the key's `units`, one per query character.
        public let positions: [Int]
    }

    static let match = 16
    static let boundary = 8
    static let firstCharacterBoundary = 10
    static let consecutive = 4
    static let gapStart = -3
    static let gapExtension = -1
    static let leading = -1
    static let leadingCap = -8
    /// Added when the query is the whole key ("notes" for "Notes").
    static let exact = 24
    /// Subtracted for every five characters of the key that the query does not cover, up to `lengthCap`.
    static let lengthCap = -6

    public static func match(_ query: [UInt32], in key: SearchKey) -> Match? {
        let m = query.count
        let n = key.count
        guard m > 0, m <= n else { return nil }
        guard isSubsequence(query, of: key.units) else { return nil }

        let text = key.units
        let none = Int.min / 4
        // score[i * n + j]: best score with query[0...i] matched and query[i] at text[j].
        var score = [Int](repeating: none, count: m * n)
        // chainBonus[i * n + j]: the bonus of the character that started the consecutive run ending at j.
        var chainBonus = [Int](repeating: 0, count: m * n)
        // fromGap[i * n + j]: true when query[i] at j was reached after a gap (or is the first character).
        var fromGap = [Bool](repeating: true, count: m * n)
        // previousIndex[i * n + j]: where query[i - 1] sits in the best alignment ending at (i, j).
        var previousIndex = [Int](repeating: -1, count: m * n)

        func bonus(_ j: Int) -> Int {
            key.boundary[j] ? (j == 0 ? firstCharacterBoundary : boundary) : 0
        }

        for j in 0..<n where text[j] == query[0] {
            let lead = max(leadingCap, leading * j)
            let b = bonus(j)
            score[j] = match + b * 2 + lead
            chainBonus[j] = b
        }

        if m > 1 {
            for i in 1..<m {
                let row = i * n
                let previousRow = (i - 1) * n
                // Best way to arrive at j after a gap: max over k <= j - 2 of score[i-1][k] + gap(j - 1 - k).
                var gapBest = none
                var gapBestIndex = -1
                for j in i..<n {
                    if j >= 2 {
                        let candidate = score[previousRow + j - 2]
                        let extended = gapBest == none ? none : gapBest + gapExtension
                        let opened = candidate == none ? none : candidate + gapStart
                        if opened >= extended {
                            gapBest = opened
                            gapBestIndex = j - 2
                        } else {
                            gapBest = extended
                        }
                    }
                    guard text[j] == query[i] else { continue }
                    let b = bonus(j)
                    var best = none
                    var bestFromGap = true
                    var bestChain = b
                    var bestPrevious = -1
                    let adjacent = score[previousRow + j - 1]
                    if adjacent != none {
                        let chain = max(chainBonus[previousRow + j - 1], consecutive)
                        let value = adjacent + match + max(b, chain)
                        best = value
                        bestFromGap = false
                        bestChain = max(b, chain)
                        bestPrevious = j - 1
                    }
                    if gapBest != none {
                        let value = gapBest + match + b
                        if value > best {
                            best = value
                            bestFromGap = true
                            bestChain = b
                            bestPrevious = gapBestIndex
                        }
                    }
                    score[row + j] = best
                    fromGap[row + j] = bestFromGap
                    chainBonus[row + j] = bestChain
                    previousIndex[row + j] = bestPrevious
                }
            }
        }

        let lastRow = (m - 1) * n
        var bestScore = none
        var bestEnd = -1
        for j in (m - 1)..<n where score[lastRow + j] > bestScore {
            bestScore = score[lastRow + j]
            bestEnd = j
        }
        guard bestEnd >= 0 else { return nil }

        var positions = [Int](repeating: 0, count: m)
        var j = bestEnd
        for i in stride(from: m - 1, through: 0, by: -1) {
            positions[i] = j
            if i > 0 {
                j = previousIndex[i * n + j]
            }
        }
        if m == n {
            bestScore += exact
        }
        bestScore += max(lengthCap, -(n - m) / 5)
        return Match(score: bestScore, positions: positions)
    }

    /// The best match of the query over several keys of one item, with the index of the key.
    public static func bestMatch(_ query: [UInt32], in keys: [SearchKey]) -> (match: Match, keyIndex: Int)? {
        var best: (match: Match, keyIndex: Int)?
        for (index, key) in keys.enumerated() {
            guard let found = match(query, in: key) else { continue }
            if best == nil || found.score > best!.match.score {
                best = (found, index)
            }
        }
        return best
    }

    static func isSubsequence(_ query: [UInt32], of text: [UInt32]) -> Bool {
        var i = 0
        for unit in text where unit == query[i] {
            i += 1
            if i == query.count {
                return true
            }
        }
        return false
    }
}
