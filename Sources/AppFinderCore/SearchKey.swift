import Foundation

/// A name prepared for fuzzy matching: folded to lower case without diacritics, separators
/// removed, and the start of every word marked.
///
/// Word starts are the first character, a character after a separator (space, `-`, `_`, `.`,
/// other punctuation), an upper case letter after a lower case one (camelCase), a letter after a
/// digit and the other way round, and every Han character (each one is a word of its own).
public struct SearchKey: Sendable, Hashable {
    /// The folded characters, as Unicode scalar values.
    public let units: [UInt32]
    /// `boundary[i]` is true when `units[i]` starts a word.
    public let boundary: [Bool]
    /// `sourceIndex[i]` is the index, in `Array(source)`, of the character `units[i]` came from.
    public let sourceIndex: [Int]

    public var isEmpty: Bool { units.isEmpty }
    public var count: Int { units.count }

    public init(_ source: String) {
        var units: [UInt32] = []
        var boundary: [Bool] = []
        var sourceIndex: [Int] = []
        units.reserveCapacity(source.unicodeScalars.count)
        var pendingBoundary = true
        var previous: CharacterClass = .separator
        for (index, character) in source.enumerated() {
            let kind = CharacterClass(character)
            if kind == .separator {
                pendingBoundary = true
                previous = .separator
                continue
            }
            let startsWord = pendingBoundary
                || kind == .han
                || previous == .han
                || (kind == .upper && previous == .lower)
                || (kind == .digit) != (previous == .digit)
            var first = true
            for scalar in Self.fold(character).unicodeScalars {
                units.append(scalar.value)
                boundary.append(first && startsWord)
                sourceIndex.append(index)
                first = false
            }
            pendingBoundary = false
            previous = kind
        }
        self.units = units
        self.boundary = boundary
        self.sourceIndex = sourceIndex
    }

    /// Folds a query the way keys are folded, without separators: "Sys Set" becomes "sysset".
    public static func foldQuery(_ query: String) -> [UInt32] {
        var result: [UInt32] = []
        for character in query where CharacterClass(character) != .separator {
            result.append(contentsOf: fold(character).unicodeScalars.map(\.value))
        }
        return result
    }

    /// The folded form of a query as a string, used as the key of the query memory.
    public static func normalizedQuery(_ query: String) -> String {
        String(String.UnicodeScalarView(foldQuery(query).compactMap(Unicode.Scalar.init)))
    }

    static func fold(_ character: Character) -> String {
        if character.isASCII {
            return String(character).lowercased()
        }
        return String(character).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
    }
}

enum CharacterClass: Equatable {
    case separator, lower, upper, digit, han, other

    init(_ character: Character) {
        if character.isWhitespace || character.isPunctuation || character.isSymbol {
            self = .separator
        } else if character.isNumber {
            self = .digit
        } else if character.isUppercase {
            self = .upper
        } else if character.isLowercase {
            self = .lower
        } else if character.unicodeScalars.contains(where: \.isHan) {
            self = .han
        } else {
            self = .other
        }
    }
}

extension Unicode.Scalar {
    var isHan: Bool {
        properties.isIdeographic
    }
}
