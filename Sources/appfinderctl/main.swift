import AppFinderControl
import Foundation

// appfinderctl app|fixture <command> [params as JSON]
//
// Sends one command to the Debug control channel of AppFinder (`app`) or of the test fixture
// (`fixture`) and prints the response, one line of JSON. Exit code 0 only when `ok` is true.

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: appfinderctl app|fixture <command> [params-json]\n".utf8))
    exit(2)
}
let target = arguments[arguments.startIndex]
let service: String
switch target {
case "app": service = ControlService.app
case "fixture": service = ControlService.fixture
default: service = target
}
let command = arguments[arguments.startIndex + 1]
var params: [String: Any] = [:]
if arguments.count >= 3 {
    let text = arguments[arguments.startIndex + 2]
    guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
        FileHandle.standardError.write(Data("params must be a JSON object\n".utf8))
        exit(2)
    }
    params = object
}
do {
    let data = try ControlClient.send(service: service, command: command, params: params)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    exit(response?["ok"] as? Bool == true ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
