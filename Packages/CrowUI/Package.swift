// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrowUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrowUI", targets: ["CrowUI"]),
    ],
    dependencies: [
        .package(path: "../CrowCore"),
        .package(path: "../CrowTerminal"),
    ],
    targets: [
        .target(name: "CrowUI", dependencies: ["CrowCore", "CrowTerminal"]),
        .testTarget(name: "CrowUITests", dependencies: ["CrowUI"]),
    ]
)
