import Foundation

/// What AppFinder remembers about the items opened from it: a decaying use score per item and
/// the queries that led to it. Stored as JSON by `UsageStore` in `AppFinderSystem`.
public struct UsageBook: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        /// The decayed use count as of `lastUsed`.
        public var score: Double
        public var lastUsed: Date
        public var count: Int
        /// Normalized query (see `SearchKey.normalizedQuery`) → times it led to this item.
        public var queries: [String: Int]
    }

    public static let currentVersion = 1
    /// The time after which a use counts half.
    public static let halfLife: TimeInterval = 14 * 24 * 3600
    static let maxEntries = 2000
    static let maxQueriesPerEntry = 20

    public var version: Int
    public var entries: [String: Entry]

    public init() {
        version = Self.currentVersion
        entries = [:]
    }

    public mutating func record(path: String, query: String, at now: Date) {
        let normalized = SearchKey.normalizedQuery(query)
        var entry = entries[path] ?? Entry(score: 0, lastUsed: now, count: 0, queries: [:])
        entry.score = Self.decayed(entry.score, from: entry.lastUsed, to: now) + 1
        entry.lastUsed = now
        entry.count += 1
        if !normalized.isEmpty {
            entry.queries[normalized, default: 0] += 1
            if entry.queries.count > Self.maxQueriesPerEntry {
                let kept = entry.queries.sorted { $0.value > $1.value }.prefix(Self.maxQueriesPerEntry)
                entry.queries = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
            }
        }
        entries[path] = entry
        if entries.count > Self.maxEntries {
            prune(now: now)
        }
    }

    public mutating func remove(path: String) {
        entries[path] = nil
    }

    /// The use score of an item now: each use counts 1 when it happened and half after `halfLife`.
    public func frecency(of path: String, now: Date) -> Double {
        guard let entry = entries[path] else { return 0 }
        return Self.decayed(entry.score, from: entry.lastUsed, to: now)
    }

    /// How much the item's rank goes up for this query: its use score, and more when the same
    /// query, or one that extends it or that it extends, led to the item before.
    public func boost(for path: String, query: String, now: Date) -> Double {
        guard let entry = entries[path] else { return 0 }
        var result = 10 * log2(1 + Self.decayed(entry.score, from: entry.lastUsed, to: now))
        let normalized = SearchKey.normalizedQuery(query)
        guard !normalized.isEmpty else { return result }
        var memory = 0.0
        for (previous, times) in entry.queries {
            let weight: Double
            if previous == normalized {
                weight = 24
            } else if previous.hasPrefix(normalized) {
                weight = 14
            } else if normalized.hasPrefix(previous) {
                weight = 10
            } else {
                continue
            }
            memory = max(memory, weight * log2(1 + Double(times)))
        }
        result += memory
        return result
    }

    /// The paths with the highest use score now, best first.
    public func mostUsed(limit: Int, now: Date) -> [String] {
        entries.keys
            .map { ($0, frecency(of: $0, now: now)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(limit)
            .map(\.0)
    }

    static func decayed(_ score: Double, from then: Date, to now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(then))
        return score * pow(0.5, elapsed / halfLife)
    }

    private mutating func prune(now: Date) {
        let keep = Set(mostUsed(limit: Self.maxEntries * 9 / 10, now: now))
        entries = entries.filter { keep.contains($0.key) }
    }
}
