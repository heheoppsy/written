// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Written",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "Written",
            path: "Sources/Written",
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "WrittenCLI",
            path: "Sources/WrittenCLI"
        ),
        .testTarget(
            name: "WrittenTests",
            dependencies: ["Written"]
        ),
    ]
)
