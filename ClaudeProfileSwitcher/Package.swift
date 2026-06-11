// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeProfileSwitcher",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeProfileSwitcher",
            path: "Sources/App"
        )
    ]
)
