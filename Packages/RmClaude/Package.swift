// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RmClaude",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RmClaude", targets: ["RmClaude"]),
    ],
    dependencies: [
        .package(path: "../RmCore"),
    ],
    targets: [
        .target(name: "RmClaude", dependencies: ["RmCore"]),
    ]
)
