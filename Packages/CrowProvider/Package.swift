// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrowProvider",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrowProvider", targets: ["CrowProvider"]),
    ],
    dependencies: [
        .package(path: "../CrowCore"),
    ],
    targets: [
        .target(name: "CrowProvider", dependencies: ["CrowCore"]),
        .testTarget(name: "CrowProviderTests", dependencies: ["CrowProvider"]),
    ]
)
