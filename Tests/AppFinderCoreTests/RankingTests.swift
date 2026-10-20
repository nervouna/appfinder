import Foundation
import Testing
@testable import AppFinderCore

@Suite struct UsageBookTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func usesDecayByHalfLife() {
        var book = UsageBook()
        book.record(path: "/a", query: "a", at: start)
        book.record(path: "/a", query: "a", at: start)
        #expect(book.frecency(of: "/a", now: start) == 2)
        #expect(abs(book.frecency(of: "/a", now: start + UsageBook.halfLife) - 1) < 1e-9)
        #expect(book.entries["/a"]?.count == 2)
    }

    @Test func remembersQueries() {
        var book = UsageBook()
        book.record(path: "/Safari.app", query: "Sa F", at: start)
        #expect(book.entries["/Safari.app"]?.queries == ["saf": 1])
    }

    @Test func queryMemoryBoostsMoreThanUseAlone() {
        var book = UsageBook()
        book.record(path: "/Safari.app", query: "s", at: start)
        let same = book.boost(for: "/Safari.app", query: "s", now: start)
        let unrelated = book.boost(for: "/Safari.app", query: "x", now: start)
        #expect(same > unrelated)
        #expect(unrelated > 0)
        #expect(book.boost(for: "/Other.app", query: "s", now: start) == 0)
    }

    @Test func prefixRelatedQueriesBoostLessThanTheSameQuery() {
        var book = UsageBook()
        book.record(path: "/Safari.app", query: "saf", at: start)
        let same = book.boost(for: "/Safari.app", query: "saf", now: start)
        let shorter = book.boost(for: "/Safari.app", query: "sa", now: start)
        let longer = book.boost(for: "/Safari.app", query: "safa", now: start)
        #expect(same > shorter)
        #expect(shorter > longer)
    }

    @Test func listsMostUsedFirst() {
        var book = UsageBook()
        book.record(path: "/a", query: "", at: start)
        book.record(path: "/b", query: "", at: start)
        book.record(path: "/b", query: "", at: start)
        #expect(book.mostUsed(limit: 5, now: start) == ["/b", "/a"])
    }

    @Test func roundTripsThroughJSON() throws {
        var book = UsageBook()
        book.record(path: "/a", query: "x", at: start)
        let data = try JSONEncoder().encode(book)
        #expect(try JSONDecoder().decode(UsageBook.self, from: data) == book)
    }
}

@Suite struct RankerTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func app(_ name: String, _ alternates: [String] = []) -> SearchItem {
        SearchItem(kind: .app, path: "/Applications/\(name).app", displayName: name, alternateNames: alternates, pinyin: true)
    }

    @Test func ranksByMatchQuality() {
        let items = [app("Messages"), app("System Settings"), app("Safari")]
        let ranked = Ranker.rank(items, query: "saf", usage: UsageBook(), now: now, limit: 10)
        #expect(ranked.first?.item.displayName == "Safari")
    }

    @Test func usageLiftsAnItem() {
        let items = [app("Terminal"), app("TextEdit")]
        let fresh = Ranker.rank(items, query: "t", usage: UsageBook(), now: now, limit: 10)
        var book = UsageBook()
        let last = fresh.last!.item
        book.record(path: last.path, query: "t", at: now)
        let learned = Ranker.rank(items, query: "t", usage: book, now: now, limit: 10)
        #expect(learned.first?.item == last)
    }

    @Test func findsLocalizedAppsByEnglishNameAndPinyin() {
        let items = [app("计算器", ["Calculator.app"].map(SearchItem.appName)), app("Calendar")]
        #expect(Ranker.rank(items, query: "calcu", usage: UsageBook(), now: now, limit: 10).first?.item.displayName == "计算器")
        #expect(Ranker.rank(items, query: "jsq", usage: UsageBook(), now: now, limit: 10).first?.item.displayName == "计算器")
    }

    @Test func highlightsTheDisplayNameOnly() {
        let items = [app("计算器", ["Calculator"])]
        let byName = Ranker.rank(items, query: "计算", usage: UsageBook(), now: now, limit: 10)
        #expect(byName.first?.highlight == [0, 1])
        let byAlternate = Ranker.rank(items, query: "calc", usage: UsageBook(), now: now, limit: 10)
        #expect(byAlternate.first?.highlight == [])
    }

    @Test func prefersTheShallowerOfTwoFilesWithTheSameName() {
        let deep = SearchItem(kind: .file, path: "/Users/me/a/b/c/notes.txt", displayName: "notes.txt")
        let shallow = SearchItem(kind: .file, path: "/Users/me/z/Notes.txt", displayName: "Notes.txt")
        let ranked = Ranker.rank([deep, shallow], query: "notes", usage: UsageBook(), now: now, limit: 10)
        #expect(ranked.map(\.item.path) == [shallow.path, deep.path])
    }

    @Test func emptyQueryMatchesNothing() {
        #expect(Ranker.rank([app("Safari")], query: "  ", usage: UsageBook(), now: now, limit: 10).isEmpty)
    }

    @Test func respectsTheLimit() {
        let items = (0..<20).map { app("Tool \($0)") }
        #expect(Ranker.rank(items, query: "tool", usage: UsageBook(), now: now, limit: 5).count == 5)
    }
}
