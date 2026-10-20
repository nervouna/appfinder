import AppFinderCore
import Foundation
import os

/// The usage book on disk: `~/Library/Application Support/AppFinder/usage.json`. Every record is
/// written right away, off the main thread, by an atomic replace.
@MainActor public final class UsageStore {
    public private(set) var book: UsageBook
    public let url: URL
    private let writer = DispatchQueue(label: "io.damao.appfinder.usage", qos: .utility)
    private nonisolated static let log = Logger(subsystem: "io.damao.appfinder", category: "usage")

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "AppFinder/usage.json")
    }

    public init(url: URL = UsageStore.defaultURL) {
        self.url = url
        book = Self.load(url)
    }

    public func record(path: String, query: String, at now: Date = Date()) {
        book.record(path: path, query: query, at: now)
        save()
    }

    public func remove(path: String) {
        book.remove(path: path)
        save()
    }

    private func save() {
        let snapshot = book
        let url = url
        writer.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(snapshot).write(to: url, options: .atomic)
            } catch {
                Self.log.error("cannot write \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Waits until every record so far is on disk.
    public func flush() {
        writer.sync {}
    }

    private static func load(_ url: URL) -> UsageBook {
        guard let data = try? Data(contentsOf: url) else { return UsageBook() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let book = try decoder.decode(UsageBook.self, from: data)
            guard book.version == UsageBook.currentVersion else {
                log.error("usage file has version \(book.version), starting empty")
                return UsageBook()
            }
            return book
        } catch {
            log.error("cannot read \(url.path, privacy: .public), starting empty: \(error.localizedDescription, privacy: .public)")
            return UsageBook()
        }
    }
}
