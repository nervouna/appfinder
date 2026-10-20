import AppFinderCore
import Carbon

/// One global hotkey, registered with Carbon's `RegisterEventHotKey`. Carbon hotkeys need no
/// permission (neither Accessibility nor Input Monitoring) and take the key press away from the
/// frontmost app.
@MainActor public final class CarbonHotkey {
    public struct RegistrationError: Error, CustomStringConvertible {
        public let status: OSStatus
        public var description: String {
            status == OSStatus(eventHotKeyExistsErr)
                ? "the shortcut is already taken by another app or the system"
                : "the system refused the shortcut (error \(status))"
        }
    }

    private static let signature: OSType = 0x4146_6E64 // 'AFnd'
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: @MainActor () -> Void
    public private(set) var shortcut: Shortcut?

    public init(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                guard status == noErr, id.signature == CarbonHotkey.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let hotkey = Unmanaged<CarbonHotkey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotkey.onPress() }
                return noErr
            },
            1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
    }

    /// Replaces the registered shortcut. On failure nothing is registered.
    public func register(_ shortcut: Shortcut) throws(RegistrationError) {
        unregister()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            Self.carbonModifiers(shortcut.modifiers),
            EventHotKeyID(signature: Self.signature, id: 1),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            throw RegistrationError(status: status)
        }
        hotKey = ref
        self.shortcut = shortcut
    }

    public func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
        shortcut = nil
    }

    static func carbonModifiers(_ modifiers: Shortcut.Modifiers) -> UInt32 {
        var result = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }
}
