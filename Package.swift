// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AppFinder",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "AppFinderCore", targets: ["AppFinderCore"]),
        .library(name: "AppFinderSystem", targets: ["AppFinderSystem"]),
        .library(name: "AppFinderControl", targets: ["AppFinderControl"]),
        .executable(name: "appfinderctl", targets: ["appfinderctl"]),
    ],
    targets: [
        // Pure logic: fuzzy matching, pinyin keys, ranking, usage model, shortcut model.
        .target(name: "AppFinderCore"),
        // Adapters: Carbon hotkey, TIS input sources, Spotlight queries, login item, usage file.
        .target(
            name: "AppFinderSystem",
            dependencies: ["AppFinderCore"]
        ),
        // Request/response protocol, server and client of the Debug control channel.
        .target(name: "AppFinderControl"),
        // Command line client of the control channel.
        .executableTarget(
            name: "appfinderctl",
            dependencies: ["AppFinderControl"]
        ),
        .testTarget(
            name: "AppFinderCoreTests",
            dependencies: ["AppFinderCore"]
        ),
        .testTarget(
            name: "AppFinderSystemTests",
            dependencies: ["AppFinderSystem", "AppFinderCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
