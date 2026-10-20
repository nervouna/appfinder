import AppFinderSystem
import AppKit

/// The menu bar item: open the panel, Settings, launch at login, quit.
@MainActor final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let hotkeys: HotkeyController
    private let openPanel: () -> Void
    private let openSettings: () -> Void

    init(hotkeys: HotkeyController, openPanel: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.hotkeys = hotkeys
        self.openPanel = openPanel
        self.openSettings = openSettings
        super.init()
        let image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "AppFinder")
        image?.isTemplate = true
        item.button?.image = image
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: String(localized: "Open AppFinder"), action: #selector(openClicked), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let shortcut = NSMenuItem(title: hotkeys.shortcut.displayText, action: nil, keyEquivalent: "")
        if let failure = hotkeys.failure {
            shortcut.title = String(localized: "Shortcut \(hotkeys.shortcut.displayText) is not available")
            shortcut.toolTip = failure
        }
        shortcut.isEnabled = false
        menu.addItem(shortcut)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: String(localized: "Settings…"), action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let login = NSMenuItem(title: String(localized: "Launch at Login"), action: #selector(loginClicked), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "Quit AppFinder"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func openClicked() {
        // Let the menu finish closing first, so the panel is not ordered out with it.
        DispatchQueue.main.async { [openPanel] in openPanel() }
    }

    @objc private func settingsClicked() {
        openSettings()
    }

    @objc private func loginClicked() {
        try? LoginItem.setEnabled(!LoginItem.isEnabled)
    }
}
