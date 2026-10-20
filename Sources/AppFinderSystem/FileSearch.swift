import AppFinderCore
import CoreServices
import Foundation
import os

/// Files and folders in the home folder whose name contains every word of the query, from the
/// Spotlight index (`MDQuery`, run synchronously on a serial queue of its own).
///
/// A search that a newer one has replaced before it ran answers nil without querying, so typing
/// quickly never builds a backlog.
public final class FileSearch: Sendable {
    public static let minimumQueryLength = 2
    /// The most results one Spotlight query returns; the ranking picks the best of them.
    public static let maxResults = 500

    private let queue = DispatchQueue(label: "io.damao.appfinder.file-search", qos: .userInitiated)
    private let latest = OSAllocatedUnfairLock(initialState: 0)
    private let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    /// The files for this query, or nil when a newer search was started before this one ran.
    public func search(_ text: String) async -> [SearchItem]? {
        let words = Self.words(text)
        let generation = latest.withLock { state in
            state += 1
            return state
        }
        guard words.joined().count >= Self.minimumQueryLength else { return [] }
        let home = home
        return await withCheckedContinuation { continuation in
            queue.async { [latest] in
                guard latest.withLock({ $0 }) == generation else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Self.run(words: words, home: home))
            }
        }
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The Spotlight query string: every word somewhere in the file name, ignoring case and diacritics.
    static func queryString(words: [String]) -> String {
        words.map { "kMDItemFSName == \"*\(escape($0))*\"cd" }.joined(separator: " && ")
    }

    static func escape(_ word: String) -> String {
        var result = ""
        for character in word {
            if character == "\\" || character == "\"" || character == "*" || character == "?" {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    private static func run(words: [String], home: String) -> [SearchItem] {
        guard let query = MDQueryCreate(kCFAllocatorDefault, queryString(words: words) as CFString, nil, nil) else {
            return []
        }
        MDQuerySetSearchScope(query, [home] as CFArray, 0)
        MDQuerySetMaxCount(query, maxResults)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var items: [SearchItem] = []
        let count = MDQueryGetResultCount(query)
        items.reserveCapacity(count)
        for index in 0..<count {
            guard let pointer = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(pointer).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  !path.hasSuffix(".app"),
                  !FileFilter.isExcluded(path: path, home: home)
            else { continue }
            let name = (path as NSString).lastPathComponent
            items.append(SearchItem(kind: .file, path: path, displayName: name))
        }
        return items
    }
}
