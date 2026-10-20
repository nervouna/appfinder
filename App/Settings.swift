import AppFinderCore
import AppFinderSystem
import AppKit
import Carbon
import Observation
import SwiftUI

/// What the Settings window shows and changes.
@MainActor @Observable final class SettingsModel {
    private(set) var shortcutText: String
    private(set) var isRecording = false
    private(set) var message: String?
    private(set) var loginItemEnabled = LoginItem.isEnabled
    private(set) var loginItemNeedsApproval = LoginItem.requiresApproval
    /// Whether AppFinder may read Desktop, Documents and Downloads (nil until checked).
    private(set) var foldersAllowed: Bool?
    @ObservationIgnored private let hotkeys: HotkeyController
    @ObservationIgnored private var monitor: Any?

    init(hotkeys: HotkeyController) {
        self.hotkeys = hotkeys
        shortcutText = hotkeys.shortcut.displayText
        message = hotkeys.failure.map { String(localized: "Shortcut \(hotkeys.shortcut.displayText) is not available") + ": \($0)" }
    }

    func refresh() {
        shortcutText = hotkeys.shortcut.displayText
        loginItemEnabled = LoginItem.isEnabled
        loginItemNeedsApproval = LoginItem.requiresApproval
        checkFolders()
    }

    /// Checks the protected folders off the main thread: the first check makes the system ask.
    func checkFolders() {
        DispatchQueue.global(qos: .utility).async {
            let allowed = FolderAccess.check().isEmpty
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.foldersAllowed = allowed }
            }
        }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(FolderAccess.privacySettings)
    }

    /// Starts recording: the global shortcut is suspended so that it can be pressed to record it again.
    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        message = nil
        hotkeys.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.recorded(event)
            }
            return nil
        }
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        hotkeys.resume()
        refresh()
    }

    func restoreDefault() {
        endRecording()
        apply(.defaultShortcut)
    }

    private func recorded(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape), event.modifierFlags.intersection(.deviceIndependentFlagsMask).isDisjoint(with: [.command, .option, .control]) {
            endRecording()
            return
        }
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: Self.modifiers(event.modifierFlags))
        guard shortcut.isValid else {
            message = String(localized: "A shortcut needs ⌘, ⌥ or ⌃, or a function key.")
            return
        }
        endRecording()
        apply(shortcut)
    }

    private func apply(_ shortcut: Shortcut) {
        if let failure = hotkeys.change(to: shortcut) {
            message = String(localized: "Shortcut \(shortcut.displayText) is not available") + ": \(failure)"
        } else {
            message = nil
        }
        refresh()
    }

    func setLoginItem(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            message = nil
        } catch {
            message = error.localizedDescription
        }
        refresh()
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Shortcut.Modifiers {
        var result: Shortcut.Modifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            LabeledContent(String(localized: "Shortcut")) {
                HStack {
                    Button(model.isRecording ? String(localized: "Type a shortcut…") : model.shortcutText) {
                        model.isRecording ? model.endRecording() : model.beginRecording()
                    }
                    .frame(minWidth: 120)
                    Button(String(localized: "Restore Default")) {
                        model.restoreDefault()
                    }
                    .disabled(model.shortcutText == Shortcut.defaultShortcut.displayText && !model.isRecording)
                }
            }
            Toggle(String(localized: "Launch at login"), isOn: Binding(
                get: { model.loginItemEnabled },
                set: { model.setLoginItem($0) }
            ))
            LabeledContent(String(localized: "Desktop, Documents and Downloads")) {
                if model.foldersAllowed == false {
                    Button(String(localized: "Open Privacy Settings")) {
                        model.openPrivacySettings()
                    }
                } else if model.foldersAllowed == true {
                    Text(String(localized: "Allowed"))
                        .foregroundStyle(.secondary)
                }
            }
            if model.foldersAllowed == false {
                Text(String(localized: "Files in these folders are found only when AppFinder may access them."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if model.loginItemNeedsApproval {
                Text(String(localized: "Allow AppFinder in System Settings → General → Login Items."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}

/// The Settings window, an `NSWindow` hosting `SettingsView`; a SwiftUI `Settings` scene cannot be
/// opened reliably from a menu bar app.
@MainActor final class SettingsController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private var window: NSWindow?

    init(hotkeys: HotkeyController) {
        model = SettingsModel(hotkeys: hotkeys)
        super.init()
        hotkeys.onChange = { [weak self] in self?.model.refresh() }
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = String(localized: "AppFinder Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        model.refresh()
        window?.makeKeyAndOrderFront(nil)
        // activateIgnoringOtherApps, deprecated but still the only option that brings a menu bar
        // app forward reliably (measured for Piccolo on macOS 27).
        NSRunningApplication.current.activate(options: NSApplication.ActivationOptions(rawValue: 1 << 1))
    }

    var isVisible: Bool { window?.isVisible == true }

    func checkFolders() {
        model.checkFolders()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model.endRecording()
    }

    func windowDidResignKey(_ notification: Notification) {
        model.endRecording()
    }
}
