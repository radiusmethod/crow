// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrowClaude",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrowClaude", targets: ["CrowClaude"]),
    ],
    dependencies: [
        .package(path: "../CrowCore"),
    ],
    targets: [
        .target(name: "CrowClaude", dependencies: ["CrowCore"]),
        .testTarget(name: "CrowClaudeTests", dependencies: ["CrowClaude"]),
    ]
)
