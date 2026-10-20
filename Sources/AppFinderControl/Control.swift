import Foundation

/// The Debug control channel: a same-user `CFMessagePort` (no network socket) that carries one
/// JSON request and one JSON response per call.
///
/// Requests are `{"command": String, "params": Object}`, responses
/// `{"ok": Bool, "result": Any?, "error": String?}`.
public enum ControlService {
    public static let app = "io.damao.appfinder.control"
    public static let fixture = "io.damao.appfinder.fixture.control"
    static let messageID: Int32 = 1
}

public struct ControlFailure: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// A server running on a thread of its own, so that a handler may wait for work on the main thread.
public final class ControlServer: @unchecked Sendable {
    /// Receives the params and returns the result (anything `JSONSerialization` can write), or throws.
    public typealias Handler = @Sendable (_ params: [String: Any]) throws -> Any?

    public let name: String
    private let handlers: [String: Handler]
    private var port: CFMessagePort?
    private var thread: Thread?

    public init(name: String, handlers: [String: Handler]) {
        self.name = name
        self.handlers = handlers
    }

    public func start() throws {
        let started = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var failure: ControlFailure?
        let thread = Thread { [self] in
            var context = CFMessagePortContext(
                version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil, release: nil, copyDescription: nil
            )
            var shouldFree: DarwinBoolean = false
            guard let port = CFMessagePortCreateLocal(nil, name as CFString, { _, _, data, info in
                guard let info else { return nil }
                let server = Unmanaged<ControlServer>.fromOpaque(info).takeUnretainedValue()
                let reply = server.handle(data.map { $0 as Data } ?? Data())
                return Unmanaged.passRetained(reply as CFData)
            }, &context, &shouldFree) else {
                failure = ControlFailure("cannot create message port \(name) (is another instance running?)")
                started.signal()
                return
            }
            self.port = port
            let source = CFMessagePortCreateRunLoopSource(nil, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            started.signal()
            CFRunLoopRun()
        }
        thread.name = "control server"
        thread.start()
        self.thread = thread
        started.wait()
        if let failure {
            throw failure
        }
    }

    func handle(_ data: Data) -> Data {
        var response: [String: Any]
        do {
            guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let command = request["command"] as? String
            else { throw ControlFailure("a request is {\"command\": String, \"params\": Object}") }
            guard let handler = handlers[command] else {
                throw ControlFailure("unknown command \(command); commands: \(handlers.keys.sorted().joined(separator: ", "))")
            }
            let result = try handler(request["params"] as? [String: Any] ?? [:])
            response = ["ok": true]
            if let result {
                response["result"] = result
            }
        } catch {
            response = ["ok": false, "error": String(describing: error)]
        }
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        return (try? JSONSerialization.data(withJSONObject: response, options: options))
            ?? Data(#"{"ok":false,"error":"the result cannot be written as JSON"}"#.utf8)
    }
}

public enum ControlClient {
    /// Sends one request and returns the raw JSON response.
    public static func send(service: String, command: String, params: [String: Any] = [:], timeout: TimeInterval = 10) throws -> Data {
        guard let remote = CFMessagePortCreateRemote(nil, service as CFString) else {
            throw ControlFailure("no server: nothing listens on \(service)")
        }
        defer { CFMessagePortInvalidate(remote) }
        let payload = try JSONSerialization.data(withJSONObject: ["command": command, "params": params])
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            remote, ControlService.messageID, payload as CFData, timeout, timeout, CFRunLoopMode.defaultMode.rawValue, &reply
        )
        guard status == kCFMessagePortSuccess, let data = reply?.takeRetainedValue() else {
            throw ControlFailure("no answer from \(service) (status \(status))")
        }
        return data as Data
    }

    /// Sends one request and returns the result of a successful response; throws the error of a failed one.
    public static func call(service: String, command: String, params: [String: Any] = [:], timeout: TimeInterval = 10) throws -> Any? {
        let data = try send(service: service, command: command, params: params, timeout: timeout)
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ControlFailure("invalid response from \(service)")
        }
        guard response["ok"] as? Bool == true else {
            throw ControlFailure(response["error"] as? String ?? "failed")
        }
        return response["result"]
    }
}
