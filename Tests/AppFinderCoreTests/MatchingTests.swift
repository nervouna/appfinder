import Foundation
import Testing
@testable import AppFinderCore

@Suite struct SearchKeyTests {
    @Test func foldsCaseAndDiacriticsAndDropsSeparators() {
        let key = SearchKey("Café-Au_Lait.app")
        #expect(String(String.UnicodeScalarView(key.units.compactMap(Unicode.Scalar.init))) == "cafeaulaitapp")
    }

    @Test func marksWordStarts() {
        let key = SearchKey("System Settings")
        let starts = key.boundary.enumerated().filter(\.element).map(\.offset)
        #expect(starts == [0, 6])
    }

    @Test func marksCamelCaseAndDigits() {
        let key = SearchKey("iTerm2 macOS")
        let starts = key.boundary.enumerated().filter(\.element).map(\.offset)
        // i, T(erm), 2, m(ac), and O(S): an upper case letter after a lower case one.
        #expect(starts == [0, 1, 5, 6, 9])
    }

    @Test func everyHanCharacterStartsAWord() {
        let key = SearchKey("QQ音乐")
        #expect(key.boundary == [true, false, true, true])
    }

    @Test func mapsUnitsToSourceCharacters() {
        let key = SearchKey("A b")
        #expect(key.sourceIndex == [0, 2])
    }

    @Test func normalizesQueries() {
        #expect(SearchKey.normalizedQuery(" Sys Set ") == "sysset")
    }
}

@Suite struct FuzzyMatcherTests {
    func score(_ query: String, _ name: String) -> Int? {
        FuzzyMatcher.match(SearchKey.foldQuery(query), in: SearchKey(name))?.score
    }

    @Test func requiresEveryCharacterInOrder() {
        #expect(score("sfr", "Safari") != nil)
        #expect(score("rfs", "Safari") == nil)
        #expect(score("safarix", "Safari") == nil)
    }

    @Test func prefixBeatsMiddle() throws {
        let prefix = try #require(score("term", "Terminal"))
        let middle = try #require(score("term", "Determine"))
        #expect(prefix > middle)
    }

    @Test func wordStartsBeatScatteredLetters() throws {
        let initials = try #require(score("ss", "System Settings"))
        let scattered = try #require(score("ss", "Messages"))
        #expect(initials > scattered)
    }

    @Test func findsTheOptimalAlignment() throws {
        // A greedy scan takes the "s" and "e" of "System"; the best alignment is "Set" of "Settings".
        let match = try #require(FuzzyMatcher.match(SearchKey.foldQuery("set"), in: SearchKey("System Settings")))
        #expect(match.positions == [6, 7, 8])
    }

    @Test func exactBeatsLonger() throws {
        let exact = try #require(score("notes", "Notes"))
        let longer = try #require(score("notes", "Notes Helper"))
        #expect(exact > longer)
    }

    @Test func consecutiveBeatsGaps() throws {
        let consecutive = try #require(score("cal", "Calendar"))
        let gaps = try #require(score("cal", "Cloud Admin Launcher"))
        #expect(consecutive > gaps)
    }

    @Test func matchesHan() {
        #expect(score("计算", "计算器") != nil)
    }
}

@Suite struct PinyinTests {
    func matches(_ query: String, _ name: String) -> Bool {
        let item = SearchItem(kind: .app, path: "/Applications/\(name).app", displayName: name, pinyin: true)
        return FuzzyMatcher.bestMatch(SearchKey.foldQuery(query), in: item.keys) != nil
    }

    @Test func fullPinyinAndInitials() {
        #expect(matches("jisuanqi", "计算器"))
        #expect(matches("jsq", "计算器"))
        #expect(matches("xtsz", "系统设置"))
        #expect(matches("weixin", "微信"))
    }

    @Test func mixedNames() {
        #expect(matches("qqyy", "QQ音乐"))
        #expect(matches("qqyinyue", "QQ音乐"))
    }

    @Test func polyphonicCharactersGetTheirOtherReadings() {
        #expect(matches("yinyue", "网易云音乐"))
        #expect(matches("yinle", "网易云音乐"))
        #expect(matches("zhaoshangyinhang", "招商银行"))
    }

    @Test func noKeyWithoutHan() {
        #expect(Pinyin.keys(for: "Safari").isEmpty)
    }

    @Test func initialsRankLikeAPrefix() throws {
        let item = SearchItem(kind: .app, path: "/x", displayName: "计算器", pinyin: true)
        let initials = try #require(FuzzyMatcher.bestMatch(SearchKey.foldQuery("jsq"), in: item.keys))
        let other = SearchItem(kind: .app, path: "/y", displayName: "Jetsquid")
        let scattered = try #require(FuzzyMatcher.bestMatch(SearchKey.foldQuery("jsq"), in: other.keys))
        #expect(initials.match.score > scattered.match.score)
    }
}

@Suite struct FileFilterTests {
    let home = "/Users/me"

    @Test func excludesLibraryHiddenPackagesAndBuildFolders() {
        #expect(FileFilter.isExcluded(path: "/Users/me/Library/Caches/x.txt", home: home))
        #expect(FileFilter.isExcluded(path: "/Users/me/.config/x.json", home: home))
        #expect(FileFilter.isExcluded(path: "/Users/me/Projects/a/node_modules/x/index.js", home: home))
        #expect(FileFilter.isExcluded(path: "/Users/me/Apps/Foo.app/Contents/Info.plist", home: home))
        #expect(FileFilter.isExcluded(path: "/Users/me/Desktop/.DS_Store", home: home))
        #expect(FileFilter.isExcluded(path: "/Users/me/Projects/x/build/sources/doc/design", home: home))
    }

    @Test func keepsOrdinaryFilesFoldersAndPackagesThemselves() {
        #expect(!FileFilter.isExcluded(path: "/Users/me/Documents/Report.pdf", home: home))
        #expect(!FileFilter.isExcluded(path: "/Users/me/Develop/Projects", home: home))
        #expect(!FileFilter.isExcluded(path: "/Users/me/Documents/Budget.numbers", home: home))
        #expect(!FileFilter.isExcluded(path: "/Users/me/Documents/v1.2 notes.txt", home: home))
    }
}

@Suite struct ShortcutTests {
    @Test func defaultIsCommandE() {
        #expect(Shortcut.defaultShortcut.displayText == "⌘E")
        #expect(Shortcut.defaultShortcut.isValid)
    }

    @Test func needsAModifierOtherThanShift() {
        #expect(!Shortcut(keyCode: 14, modifiers: []).isValid)
        #expect(!Shortcut(keyCode: 14, modifiers: [.shift]).isValid)
        #expect(Shortcut(keyCode: 49, modifiers: [.option]).isValid)
        #expect(Shortcut(keyCode: 105, modifiers: []).isValid)
    }

    @Test func writesModifiersInMenuOrder() {
        let shortcut = Shortcut(keyCode: 49, modifiers: [.command, .shift, .option, .control])
        #expect(shortcut.displayText == "⌃⌥⇧⌘Space")
    }

    @Test func roundTripsThroughJSON() throws {
        let shortcut = Shortcut(keyCode: 49, modifiers: [.option])
        let data = try JSONEncoder().encode(shortcut)
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == shortcut)
    }
}
