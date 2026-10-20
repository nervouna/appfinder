import AppFinderCore
import AppFinderSystem
import AppKit
import os

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let catalog = AppCatalog()
    private let usage = UsageStore()
    private let inputSources = TISInputSources()
    private(set) var search: SearchController!
    private(set) var hotkeys: HotkeyController!
    private var statusMenu: StatusMenu!
    private(set) var settings: SettingsController!
    private let log = Logger(subsystem: "io.damao.appfinder", category: "app")
    #if DEBUG
    private var debugServer: DebugControl?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        search = SearchController(catalog: catalog, usage: usage, inputSources: inputSources)
        hotkeys = HotkeyController { [weak self] in self?.search.toggle() }
        settings = SettingsController(hotkeys: hotkeys)
        statusMenu = StatusMenu(
            hotkeys: hotkeys,
            openPanel: { [weak self] in self?.search.show() },
            openSettings: { [weak self] in self?.settings.show() }
        )
        catalog.start()
        hotkeys.registerSaved()
        #if !DEBUG
        offerLoginItemOnce()
        #endif
        #if DEBUG
        debugServer = DebugControl(app: self)
        debugServer?.start()
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching AppFinder again while it runs opens Settings.
        settings.show()
        return false
    }

    /// AppFinder launches at login: it registers itself on its first launch, once. The switch in
    /// Settings and the menu turn it off and on afterwards.
    private func offerLoginItemOnce() {
        guard !Preferences.loginItemOffered else { return }
        Preferences.loginItemOffered = true
        do {
            try LoginItem.setEnabled(true)
        } catch {
            log.error("cannot register the login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The global shortcut: registers the saved one at launch and replaces it when Settings records
/// another. Recording suspends it, so that the current shortcut itself can be recorded again.
@MainActor final class HotkeyController {
    private var hotkey: CarbonHotkey!
    private(set) var shortcut: Shortcut = Preferences.shortcut
    /// Why the shortcut is not registered, or nil when it is.
    private(set) var failure: String?
    var onChange: (() -> Void)?
    private let log = Logger(subsystem: "io.damao.appfinder", category: "hotkey")

    init(onPress: @escaping @MainActor () -> Void) {
        hotkey = CarbonHotkey(onPress: onPress)
    }

    func registerSaved() {
        apply(Preferences.shortcut)
    }

    /// Registers a new shortcut and saves it; on failure the previous one stays registered and saved.
    @discardableResult func change(to shortcut: Shortcut) -> String? {
        let previous = self.shortcut
        do {
            try hotkey.register(shortcut)
            self.shortcut = shortcut
            failure = nil
            Preferences.shortcut = shortcut
            onChange?()
            return nil
        } catch {
            apply(previous)
            return error.description
        }
    }

    func suspend() {
        hotkey.unregister()
    }

    func resume() {
        apply(shortcut)
    }

    private func apply(_ shortcut: Shortcut) {
        self.shortcut = shortcut
        do {
            try hotkey.register(shortcut)
            failure = nil
        } catch {
            failure = error.description
            log.error("cannot register \(shortcut.displayText, privacy: .public): \(error.description, privacy: .public)")
        }
        onChange?()
    }
}
