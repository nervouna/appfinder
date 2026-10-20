#if DEBUG
import AppFinderControl
import AppFinderSystem
import AppKit

/// The Debug control channel (`io.damao.appfinder.control`): lets scripts open and close the
/// panel through the same code paths as the hotkey and Esc, and read what happened, without
/// posting key events. Release builds contain none of this.
@MainActor final class DebugControl {
    private let server: ControlServer

    init(app: AppDelegate) {
        let handlers: [String: ControlServer.Handler] = [
            "status": { _ in
                onMain { done in
                    done([
                        "pid": ProcessInfo.processInfo.processIdentifier,
                        "bundle": Bundle.main.bundlePath,
                        "shortcut": app.hotkeys.shortcut.displayText,
                        "hotkeyFailure": app.hotkeys.failure ?? NSNull(),
                        "loginItem": LoginItem.statusName,
                    ] as [String: Any])
                }
            },
            "panel.state": { _ in
                onMain { done in done(app.search.debugState()) }
            },
            // Opens the panel as the hotkey does; answers once the run loop has passed once more.
            "panel.show": { _ in
                onMain { done in
                    app.search.toggleIfClosed()
                    DispatchQueue.main.async { done(app.search.debugState()) }
                }
            },
            // The hotkey's action: opens or closes. Answers after a close has finished.
            "panel.toggle": { _ in
                onMain { done in
                    if app.search.isOpen {
                        app.search.close(.hotkey) { done(app.search.debugState()) }
                    } else {
                        app.search.toggle()
                        DispatchQueue.main.async { done(app.search.debugState()) }
                    }
                }
            },
            // Closes as Esc does and answers once the panel is gone and the source is handed back.
            "panel.hide": { _ in
                onMain { done in
                    guard app.search.isOpen else {
                        done(app.search.debugState())
                        return
                    }
                    app.search.close(.escape) { done(app.search.debugState()) }
                }
            },
            // Sets the query as typing would; `waitMs` gives the file search time to answer.
            "panel.query": { params in
                guard let text = params["text"] as? String else { throw ControlFailure("params: {text, waitMs?}") }
                let wait = params["waitMs"] as? Double ?? 0
                return onMain { done in
                    app.search.setQuery(text)
                    DispatchQueue.main.asyncAfter(deadline: .now() + wait / 1000) { done(app.search.debugState()) }
                }
            },
            "panel.probe": { _ in
                onMain { done in done(app.search.debugProbe()) }
            },
            // Sends a key press through NSApp.sendEvent, as the window server's event would arrive:
            // {keyCode, command?, shift?}.
            "panel.key": { params in
                guard let code = params["keyCode"] as? Int else { throw ControlFailure("params: {keyCode, command?, shift?}") }
                let command = params["command"] as? Bool ?? false
                let shift = params["shift"] as? Bool ?? false
                return onMain { done in
                    let source = CGEventSource(stateID: .privateState)
                    for down in [true, false] {
                        guard let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { continue }
                        var flags: CGEventFlags = []
                        if command { flags.insert(.maskCommand) }
                        if shift { flags.insert(.maskShift) }
                        cgEvent.flags = flags
                        if let event = NSEvent(cgEvent: cgEvent) {
                            NSApp.sendEvent(event)
                        }
                    }
                    DispatchQueue.main.async { done(app.search.debugState()) }
                }
            },
            "inputSource.current": { _ in
                onMain { done in done(["id": (TISInputSources().currentID() as Any?) ?? NSNull()]) }
            },
            "tuning.set": { params in
                let settle = params["settleMs"] as? Double
                let timeout = params["reportTimeoutMs"] as? Double
                return onMain { done in
                    if let settle {
                        app.search.tuning.settle = .milliseconds(settle)
                    }
                    if let timeout {
                        app.search.tuning.reportTimeout = .milliseconds(timeout)
                    }
                    done(["settle": "\(app.search.tuning.settle)", "reportTimeout": "\(app.search.tuning.reportTimeout)"])
                }
            },
            "settings.open": { _ in
                onMain { done in
                    app.settings.show()
                    done(["visible": app.settings.isVisible])
                }
            },
            "settings.close": { _ in
                onMain { done in
                    app.settings.close()
                    done(["visible": app.settings.isVisible])
                }
            },
        ]
        server = ControlServer(name: ControlService.app, handlers: handlers)
    }

    func start() {
        do {
            try server.start()
        } catch {
            NSLog("AppFinder: debug control server not started: \(error)")
        }
    }
}

/// Runs `body` on the main thread and waits for it to call `done` (from the server's thread).
private func onMain(_ body: @escaping @MainActor (@escaping (Any?) -> Void) -> Void) -> Any? {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Any?
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            body { value in
                result = value
                semaphore.signal()
            }
        }
    }
    semaphore.wait()
    return result
}

extension SearchController {
    /// Opens the panel unless it is open (`panel.show` must never close it).
    func toggleIfClosed() {
        if !isOpen {
            toggle()
        }
    }
}
#endif
