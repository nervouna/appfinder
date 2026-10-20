import AppFinderCore
import Foundation
import Testing
@testable import AppFinderSystem

@MainActor final class FakeInputSources: InputSourceBackend {
    var current: String?
    var selections: [String] = []
    /// Sources whose selection the fake ignores, as the system does for one that is not enabled.
    var refused: Set<String> = []

    init(_ current: String?) {
        self.current = current
    }

    func currentID() -> String? { current }

    func select(_ id: String) -> Bool {
        selections.append(id)
        guard !refused.contains(id) else { return false }
        current = id
        return true
    }
}

@MainActor @Suite struct InputSourceLockTests {
    let inkflow = "io.damao.inputmethod.inkflow.Hans"

    @Test func locksToABCAndRestoresThePreviousSource() {
        let backend = FakeInputSources(inkflow)
        let lock = InputSourceLock(backend: backend)
        #expect(lock.engage())
        #expect(backend.current == InputSourceLock.abc)
        #expect(lock.saved == inkflow)
        #expect(lock.restore() == inkflow)
        #expect(backend.current == inkflow)
        #expect(backend.selections == [InputSourceLock.abc, inkflow])
        #expect(!lock.isEngaged)
    }

    @Test func selectsNothingWhenABCWasSelectedAlready() {
        let backend = FakeInputSources(InputSourceLock.abc)
        let lock = InputSourceLock(backend: backend)
        lock.engage()
        #expect(lock.restore() == nil)
        #expect(backend.selections.isEmpty)
    }

    @Test func engagingTwiceKeepsTheFirstSavedSource() {
        let backend = FakeInputSources(inkflow)
        let lock = InputSourceLock(backend: backend)
        lock.engage()
        lock.engage()
        #expect(lock.saved == inkflow)
    }

    @Test func holdTargetSelectsABCAgainAfterASwitch() {
        let backend = FakeInputSources(inkflow)
        let lock = InputSourceLock(backend: backend)
        lock.engage()
        backend.current = "com.apple.inputmethod.SCIM.ITABC"
        #expect(lock.holdTarget())
        #expect(backend.current == InputSourceLock.abc)
        #expect(lock.restore() == inkflow)
    }

    @Test func reportsATargetThatCannotBeSelected() {
        let backend = FakeInputSources(inkflow)
        backend.refused = [InputSourceLock.abc]
        let lock = InputSourceLock(backend: backend)
        #expect(!lock.engage())
        // Nothing changed, so nothing is restored.
        #expect(lock.restore() == nil)
    }

    @Test func abandonForgetsWithoutSelecting() {
        let backend = FakeInputSources(inkflow)
        let lock = InputSourceLock(backend: backend)
        lock.engage()
        lock.abandon()
        #expect(!lock.isEngaged)
        #expect(lock.restore() == nil)
        #expect(backend.selections == [InputSourceLock.abc])
    }

    @Test func restoreWithoutEngageDoesNothing() {
        let backend = FakeInputSources(inkflow)
        let lock = InputSourceLock(backend: backend)
        #expect(lock.restore() == nil)
        #expect(backend.selections.isEmpty)
        #expect(!lock.holdTarget())
    }
}

@Suite struct FileSearchQueryTests {
    @Test func everyWordMustBeInTheName() {
        #expect(FileSearch.queryString(words: ["proj", "Notes"])
            == #"kMDItemFSName == "*proj*"cd && kMDItemFSName == "*Notes*"cd"#)
    }

    @Test func escapesQuotesAndWildcards() {
        #expect(FileSearch.escape(#"a"b*c?\"#) == #"a\"b\*c\?\\"#)
    }

    @Test func splitsOnWhitespace() {
        #expect(FileSearch.words("  a  b\tc ") == ["a", "b", "c"])
    }
}

@Suite struct AppCatalogTests {
    @Test func leavesOutAppsInsideBundles() {
        #expect(AppCatalog.isTopLevelBundle("/Applications/Safari.app"))
        #expect(AppCatalog.isTopLevelBundle("/Applications/Utilities/Terminal.app"))
        #expect(!AppCatalog.isTopLevelBundle("/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"))
    }

    @Test func dropsPlaceholderAlternateNames() {
        #expect(AppCatalog.isPlaceholder("ALTERNATE_NAME_1"))
        #expect(!AppCatalog.isPlaceholder("System Preferences"))
        #expect(!AppCatalog.isPlaceholder("Maps.app"))
        #expect(!AppCatalog.isPlaceholder("TV"))
    }
}

@MainActor @Suite struct UsageStoreTests {
    @Test func writesAndReadsTheBook() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "appfinder-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "usage.json")
        let store = UsageStore(url: url)
        store.record(path: "/Applications/Safari.app", query: "saf")
        store.flush()
        let reread = UsageStore(url: url)
        #expect(reread.book.entries["/Applications/Safari.app"]?.queries == ["saf": 1])
    }

    @Test func startsEmptyFromAnUnreadableFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "appfinder-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "usage.json")
        try Data("not json".utf8).write(to: url)
        #expect(UsageStore(url: url).book.entries.isEmpty)
    }
}
