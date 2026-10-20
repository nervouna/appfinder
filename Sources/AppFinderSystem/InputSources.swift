import AppKit
import Carbon

/// Reads and selects the system's keyboard input source.
@MainActor public protocol InputSourceBackend: AnyObject {
    /// The ID of the selected keyboard input source (`com.apple.keylayout.ABC`, `io.damao.inputmethod.inkflow.Hans`).
    func currentID() -> String?
    /// Selects the source with this ID; false when there is no such enabled source or the system refused.
    @discardableResult func select(_ id: String) -> Bool
}

/// The Text Input Sources (TIS) implementation. TIS is used from the main thread only.
@MainActor public final class TISInputSources: InputSourceBackend {
    private var cache: [String: TISInputSource] = [:]
    private var observer: NSObjectProtocol?

    public init() {
        // A source that is enabled, disabled or reinstalled gets a new TISInputSource.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cache.removeAll() }
        }
    }

    public func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return Self.id(of: source)
    }

    @discardableResult public func select(_ id: String) -> Bool {
        guard let source = source(id) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    /// The ID of an enabled ASCII capable keyboard layout, for a Mac without ABC.
    public func asciiCapableLayoutID() -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return Self.id(of: source)
    }

    public func isEnabled(_ id: String) -> Bool {
        source(id) != nil
    }

    private func source(_ id: String) -> TISInputSource? {
        if let cached = cache[id] {
            return cached
        }
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first
        else { return nil }
        cache[id] = source
        return source
    }

    static func id(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

/// Holds the input source on ABC while the panel is open and gives back the one in use before.
///
/// `engage()` runs when the panel opens and remembers the selected source; `restore()` runs when
/// it closes, while the panel still has the key focus (see `docs/design.md`, "ABC lock and restore").
@MainActor public final class InputSourceLock {
    public static let abc = "com.apple.keylayout.ABC"

    public let backend: InputSourceBackend
    /// The source the lock holds while engaged.
    public let target: String
    /// The source selected when the lock was engaged; nil while it is not.
    public private(set) var saved: String?
    public private(set) var isEngaged = false

    public init(backend: InputSourceBackend, target: String = InputSourceLock.abc) {
        self.backend = backend
        self.target = target
    }

    /// Remembers the selected source and selects the target. Returns whether the target is selected.
    @discardableResult public func engage() -> Bool {
        if !isEngaged {
            isEngaged = true
            saved = backend.currentID()
        }
        return holdTarget()
    }

    /// Selects the target again when something else took over while the lock is engaged.
    @discardableResult public func holdTarget() -> Bool {
        guard isEngaged else { return false }
        if backend.currentID() == target {
            return true
        }
        backend.select(target)
        return backend.currentID() == target
    }

    /// Disengages without selecting anything, for when the system picks the source itself.
    public func abandon() {
        isEngaged = false
        saved = nil
    }

    /// Selects the remembered source again and disengages. Returns the source it selected, or nil
    /// when nothing had to change (the source was the target already, or nothing was remembered).
    @discardableResult public func restore() -> String? {
        guard isEngaged else { return nil }
        isEngaged = false
        defer { saved = nil }
        guard let saved, saved != backend.currentID() else { return nil }
        backend.select(saved)
        return saved
    }
}

/// The system's input source settings.
public enum InputSourcePreferences {
    /// "Automatically switch to a document's input source" (Keyboard → Input Sources): every text
    /// context keeps its own source, and the system selects it when the context gets the focus.
    public static var perDocumentSources: Bool {
        let value = CFPreferencesCopyAppValue(
            "AppleGlobalTextInputProperties" as CFString, "com.apple.HIToolbox" as CFString
        ) as? [String: Any]
        return (value?["TextInputGlobalPropertyPerContextInput"] as? NSNumber)?.boolValue ?? false
    }
}
