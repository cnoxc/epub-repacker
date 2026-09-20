// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EPUBRepacker",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "EPUBRepackerCore", targets: ["EPUBRepackerCore"]),
        .executable(name: "EPUBRepackerApp", targets: ["EPUBRepackerApp"]),
        .executable(name: "TestRunner", targets: ["TestRunner"])
    ],
    targets: [
        .target(
            name: "EPUBRepackerCore",
            dependencies: []
        ),
        .executableTarget(
            name: "EPUBRepackerApp",
            dependencies: ["EPUBRepackerCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: ["EPUBRepackerCore"]
        )
    ]
)
