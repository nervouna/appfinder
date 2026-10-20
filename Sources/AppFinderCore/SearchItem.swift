import Foundation

/// Something AppFinder can open: an app from the catalog or a file from a Spotlight query.
public struct SearchItem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        case app, file
    }

    public let kind: Kind
    /// The absolute path, which is also the identity of the item in the usage book.
    public let path: String
    /// The name shown in the list (an app's localized name, a file's name).
    public let displayName: String
    /// What the query is matched against; the first key is always the display name.
    public let keys: [SearchKey]

    public var id: String { path }

    public init(kind: Kind, path: String, displayName: String, alternateNames: [String] = [], pinyin: Bool = false) {
        self.kind = kind
        self.path = path
        self.displayName = displayName
        var keys = [SearchKey(displayName)]
        var seen: Set<[UInt32]> = [keys[0].units]
        for name in alternateNames {
            let key = SearchKey(name)
            guard !key.isEmpty, seen.insert(key.units).inserted else { continue }
            keys.append(key)
        }
        if pinyin {
            for name in [displayName] + alternateNames {
                for key in Pinyin.keys(for: name) where seen.insert(key.units).inserted {
                    keys.append(key)
                }
            }
        }
        self.keys = keys
    }

    /// An app's names without the `.app` extension that `kMDItemFSName` and the alternate names carry.
    public static func appName(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
