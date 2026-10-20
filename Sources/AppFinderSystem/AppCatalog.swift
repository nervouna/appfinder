import AppFinderCore
import Foundation
import os

/// The installed apps, from a live Spotlight query that follows installs and removals.
///
/// Apps are matched on their display name (localized: 计算器), their alternate names
/// (`kMDItemAlternateNames`: Calculator, and for System Settings also Preferences and System
/// Preferences) and the pinyin of both. Apps inside other bundles are left out.
@MainActor public final class AppCatalog {
    public private(set) var items: [SearchItem] = []
    /// Called on the main actor after `items` changed.
    public var onChange: (@MainActor () -> Void)?

    public static let scopes: [String] = [
        "/Applications",
        NSHomeDirectory() + "/Applications",
        "/System/Applications",
        "/System/Library/CoreServices/Applications",
    ]
    /// Apps outside the scopes that belong in the list.
    public static let extraApps: [String] = [
        "/System/Library/CoreServices/Finder.app",
    ]

    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    private let log = Logger(subsystem: "io.damao.appfinder", category: "catalog")

    public init() {}

    public func start() {
        guard observers.isEmpty else { return }
        query.predicate = NSPredicate(
            format: "%K == %@", NSMetadataItemContentTypeTreeKey, "com.apple.application-bundle"
        )
        query.searchScopes = Self.scopes.filter { FileManager.default.fileExists(atPath: $0) }
        query.notificationBatchingInterval = 1
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
        }
        query.start()
    }

    private struct RawApp: Sendable {
        let path: String
        let displayName: String
        let alternateNames: [String]
    }

    private func reload() {
        query.disableUpdates()
        var raw: [RawApp] = []
        raw.reserveCapacity(query.resultCount)
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let app = Self.rawApp(item)
            else { continue }
            raw.append(app)
        }
        query.enableUpdates()
        for path in Self.extraApps {
            if let item = NSMetadataItem(url: URL(fileURLWithPath: path)), let app = Self.rawApp(item) {
                raw.append(app)
            }
        }
        if raw.isEmpty {
            // Spotlight indexing is off for these folders: list their top level instead.
            raw = Self.scanScopes()
            log.notice("Spotlight found no apps, scanned the folders instead: \(raw.count) apps")
        }
        generation += 1
        let current = generation
        let started = Date()
        Task.detached(priority: .userInitiated) {
            let items = raw.map {
                SearchItem(kind: .app, path: $0.path, displayName: $0.displayName,
                           alternateNames: $0.alternateNames, pinyin: true)
            }
            await MainActor.run {
                guard current == self.generation else { return }
                self.items = items
                self.log.info("catalog: \(items.count) apps in \(Date().timeIntervalSince(started), format: .fixed(precision: 3)) s")
                self.onChange?()
            }
        }
    }

    private static func rawApp(_ item: NSMetadataItem) -> RawApp? {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
              isTopLevelBundle(path)
        else { return nil }
        let fsName = (item.value(forAttribute: NSMetadataItemFSNameKey) as? String) ?? (path as NSString).lastPathComponent
        let displayName = SearchItem.appName(
            (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                ?? FileManager.default.displayName(atPath: path)
        )
        var alternates = [SearchItem.appName(fsName)]
        if let names = item.value(forAttribute: "kMDItemAlternateNames") as? [String] {
            alternates += names.filter { !isPlaceholder($0) }.map(SearchItem.appName)
        }
        return RawApp(path: path, displayName: displayName, alternateNames: alternates)
    }

    /// Whether an alternate name is a localization key that was never filled in (Maps and
    /// Weather list `ALTERNATE_NAME_1`).
    nonisolated static func isPlaceholder(_ name: String) -> Bool {
        name.contains("_") && name.allSatisfy { $0 == "_" || $0.isNumber || ($0.isUppercase && $0.isASCII) }
    }

    /// Whether no folder the app lies in is itself a bundle (`Xcode.app/Contents/.../Simulator.app`).
    nonisolated static func isTopLevelBundle(_ path: String) -> Bool {
        let parents = (path as NSString).deletingLastPathComponent
        return !parents.contains(".app/") && !parents.hasSuffix(".app")
    }

    private static func scanScopes() -> [RawApp] {
        var result: [RawApp] = []
        let manager = FileManager.default
        for scope in scopes + ["/Applications/Utilities", "/System/Applications/Utilities"] {
            guard let names = try? manager.contentsOfDirectory(atPath: scope) else { continue }
            for name in names where name.hasSuffix(".app") {
                let path = scope + "/" + name
                result.append(RawApp(path: path, displayName: SearchItem.appName(manager.displayName(atPath: path)),
                                     alternateNames: [SearchItem.appName(name)]))
            }
        }
        return result + extraApps.map {
            RawApp(path: $0, displayName: SearchItem.appName(manager.displayName(atPath: $0)),
                   alternateNames: [SearchItem.appName(($0 as NSString).lastPathComponent)])
        }
    }
}
