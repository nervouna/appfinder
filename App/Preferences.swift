import AppFinderCore
import Foundation

/// The settings kept in AppFinder's defaults domain (`io.damao.appfinder`).
@MainActor enum Preferences {
    private static let shortcutKey = "shortcut"
    private static let loginItemOfferedKey = "loginItemOffered"

    static var shortcut: Shortcut {
        get {
            guard let data = UserDefaults.standard.data(forKey: shortcutKey),
                  let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data),
                  shortcut.isValid
            else { return .defaultShortcut }
            return shortcut
        }
        set {
            if newValue == .defaultShortcut {
                UserDefaults.standard.removeObject(forKey: shortcutKey)
            } else if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: shortcutKey)
            }
        }
    }

    /// Whether AppFinder has registered itself as a login item once, on its first launch.
    static var loginItemOffered: Bool {
        get { UserDefaults.standard.bool(forKey: loginItemOfferedKey) }
        set { UserDefaults.standard.set(newValue, forKey: loginItemOfferedKey) }
    }
}
