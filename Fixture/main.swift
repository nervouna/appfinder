import AppFinderControl
import AppKit
import Carbon

// AppFinderFixture: a test app with one text view, the app the panel opens over in the input
// source checks. Debug only, never part of a release. Its control server
// (`io.damao.appfinder.fixture.control`) reports what the text view's own input context sees.

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    let window = NSWindow(
        contentRect: NSRect(x: 40, y: 60, width: 480, height: 240),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
    private var server: ControlServer?
    private(set) var activations = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.title = "AppFinder Fixture"
        window.isReleasedWhenClosed = false
        textView.font = .systemFont(ofSize: 18)
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.documentView = textView
        scroll.autoresizingMask = [.width, .height]
        textView.autoresizingMask = [.width]
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.activations += 1 }
        }

        nonisolated(unsafe) let fixture = self
        server = ControlServer(name: ControlService.fixture, handlers: [
            "state": { _ in fixtureOnMain { fixture.state() } },
            "focus": { _ in
                fixtureOnMain {
                    fixture.window.makeKeyAndOrderFront(nil)
                    fixture.window.makeFirstResponder(fixture.textView)
                    NSRunningApplication.current.activate(options: NSApplication.ActivationOptions(rawValue: 1 << 1))
                    return fixture.state()
                }
            },
            // Selects a source from inside the fixture, while its text view is focused, as a person
            // switching with the menu bar or Ctrl+Space would.
            "select": { params in
                guard let id = params["id"] as? String else { throw ControlFailure("params: {id}") }
                return fixtureOnMain {
                    fixture.textView.inputContext?.selectedKeyboardInputSource = id
                    return fixture.state()
                }
            },
            // Takes the key focus back from a panel of another app, as a click into the window would.
            "takeKey": { params in
                let variant = params["variant"] as? String ?? "orderFront"
                return fixtureOnMain {
                    switch variant {
                    case "reorder":
                        fixture.window.orderOut(nil)
                        fixture.window.makeKeyAndOrderFront(nil)
                    case "deactivate":
                        NSApp.deactivate()
                        NSRunningApplication.current.activate(options: NSApplication.ActivationOptions(rawValue: 1 << 1))
                        fixture.window.makeKeyAndOrderFront(nil)
                    default:
                        fixture.window.orderFrontRegardless()
                        fixture.window.makeKey()
                    }
                    fixture.window.makeFirstResponder(fixture.textView)
                    return fixture.state()
                }
            },
            "clear": { _ in fixtureOnMain { fixture.textView.string = ""; return fixture.state() } },
            // Types "ni" into the text view with in-process key events, which go through the text
            // view's input context and so through the input method that is really active for it:
            // InkFlow composes (marked text), ABC inserts "ni". Then discards the composition.
            "probe": { _ in
                fixtureOnMain { fixture.probe() }
            },
            "quit": { _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
                return nil
            },
        ])
        try? server?.start()
        NSRunningApplication.current.activate(options: NSApplication.ActivationOptions(rawValue: 1 << 1))
    }

    func probe() -> [String: Any] {
        textView.string = ""
        let source = CGEventSource(stateID: .privateState)
        for code in [CGKeyCode(kVK_ANSI_N), CGKeyCode(kVK_ANSI_I)] {
            for down in [true, false] {
                guard let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down),
                      let event = NSEvent(cgEvent: cgEvent)
                else { continue }
                if textView.inputContext?.handleEvent(event) != true, down {
                    textView.keyDown(with: event)
                }
            }
        }
        var result = state()
        result["composed"] = textView.hasMarkedText()
        textView.inputContext?.discardMarkedText()
        textView.unmarkText()
        textView.string = ""
        return result
    }

    func state() -> [String: Any] {
        let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let tis = current.flatMap { source -> String? in
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        }
        return [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "active": NSApp.isActive,
            "key": window.isKeyWindow,
            "textFocused": window.firstResponder === textView,
            "tis": tis ?? NSNull(),
            "contextSource": textView.inputContext?.selectedKeyboardInputSource ?? NSNull(),
            "markedText": textView.hasMarkedText(),
            "text": textView.string,
            "activations": activations,
        ]
    }
}

private func fixtureOnMain(_ body: @escaping @MainActor () -> Any?) -> Any? {
    nonisolated(unsafe) var result: Any?
    DispatchQueue.main.sync {
        MainActor.assumeIsolated {
            result = body()
        }
    }
    return result
}

let application = NSApplication.shared
let fixtureDelegate = FixtureDelegate()
application.delegate = fixtureDelegate
application.setActivationPolicy(.regular)
application.run()
