/// A global shortcut: a virtual key code and modifiers.
///
/// A valid shortcut has at least one of command, option or control, or is a function key on its
/// own; shift alone never makes one, so a plain key can never be taken from every app.
public struct Shortcut: Codable, Sendable, Hashable {
    public struct Modifiers: OptionSet, Codable, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌘E, the shortcut Raycast had on the owner's Mac.
    public static let defaultShortcut = Shortcut(keyCode: KeyNames.keyE, modifiers: [.command])

    public var isValid: Bool {
        guard KeyNames.name(for: keyCode) != nil else { return false }
        return !modifiers.isDisjoint(with: [.command, .option, .control]) || KeyNames.isFunctionKey(keyCode)
    }

    /// The shortcut as the menus write it: ⌃⌥⇧⌘ in that order, then the key ("⌘E", "⌥Space").
    public var displayText: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (KeyNames.name(for: keyCode) ?? "Key \(keyCode)")
    }
}

/// Names of the virtual key codes on an ANSI (ABC, US) keyboard.
public enum KeyNames {
    public static let keyE: UInt32 = 14
    public static let escape: UInt32 = 53

    static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help", 115: "Home", 116: "Page Up", 117: "⌦", 118: "F4", 119: "End",
        120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
        64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static let functionKeys: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    public static func name(for keyCode: UInt32) -> String? {
        names[keyCode]
    }

    public static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        functionKeys.contains(keyCode)
    }
}
