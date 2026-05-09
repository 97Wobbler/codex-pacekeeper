// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "codex-pacekeeper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CodexPacekeeperCore", targets: ["CodexPacekeeperCore"]),
        .executable(name: "CodexPacekeeper", targets: ["CodexPacekeeper"])
    ],
    targets: [
        .target(
            name: "CodexPacekeeperCore",
            path: "Sources/CodexPacekeeperCore"
        ),
        .executableTarget(
            name: "CodexPacekeeper",
            dependencies: ["CodexPacekeeperCore"],
            path: "Sources/CodexPacekeeper"
        ),
        .testTarget(
            name: "CodexPacekeeperTests",
            dependencies: ["CodexPacekeeperCore"],
            path: "Tests/CodexPacekeeperTests"
        )
    ]
)
