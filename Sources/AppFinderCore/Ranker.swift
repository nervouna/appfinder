import Foundation

/// An item that matched a query, with its rank and what to highlight.
public struct RankedItem: Sendable, Equatable, Identifiable {
    public let item: SearchItem
    public let matchScore: Int
    public let usageBoost: Double
    /// Indices into `Array(item.displayName)` of the matched characters; empty when the match was
    /// on another name (an English alternate name, the pinyin).
    public let highlight: [Int]

    public var id: String { item.id }
    public var total: Double { Double(matchScore) + usageBoost }

    public init(item: SearchItem, matchScore: Int = 0, usageBoost: Double = 0, highlight: [Int] = []) {
        self.item = item
        self.matchScore = matchScore
        self.usageBoost = usageBoost
        self.highlight = highlight
    }
}

public enum Ranker {
    /// A match must score at least this much per query character to be listed, which drops
    /// alignments scattered over a long name.
    static let minimumPerCharacter = 6

    /// The items that match the query, best first: match score plus the usage boost, then the
    /// shorter name, then the name in order, then the shallower path.
    public static func rank(
        _ items: [SearchItem],
        query: String,
        usage: UsageBook,
        now: Date,
        limit: Int
    ) -> [RankedItem] {
        let folded = SearchKey.foldQuery(query)
        guard !folded.isEmpty else { return [] }
        var results: [RankedItem] = []
        for item in items {
            guard let (match, keyIndex) = FuzzyMatcher.bestMatch(folded, in: item.keys),
                  match.score >= minimumPerCharacter * folded.count
            else { continue }
            let highlight: [Int]
            if keyIndex == 0 {
                let key = item.keys[0]
                highlight = Array(Set(match.positions.map { key.sourceIndex[$0] })).sorted()
            } else {
                highlight = []
            }
            results.append(RankedItem(
                item: item,
                matchScore: match.score,
                usageBoost: usage.boost(for: item.path, query: query, now: now),
                highlight: highlight
            ))
        }
        results.sort(by: ordered)
        return Array(results.prefix(limit))
    }

    static func ordered(_ lhs: RankedItem, _ rhs: RankedItem) -> Bool {
        if lhs.total != rhs.total {
            return lhs.total > rhs.total
        }
        if lhs.item.displayName.count != rhs.item.displayName.count {
            return lhs.item.displayName.count < rhs.item.displayName.count
        }
        let lhsName = lhs.item.displayName.lowercased()
        let rhsName = rhs.item.displayName.lowercased()
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        // Of two items with the same name, the one nearer the top of the folder tree.
        let lhsDepth = lhs.item.path.count { $0 == "/" }
        let rhsDepth = rhs.item.path.count { $0 == "/" }
        if lhsDepth != rhsDepth {
            return lhsDepth < rhsDepth
        }
        return lhs.item.path < rhs.item.path
    }
}
