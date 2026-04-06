// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrowPersistence",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrowPersistence", targets: ["CrowPersistence"]),
    ],
    dependencies: [
        .package(path: "../CrowCore"),
    ],
    targets: [
        .target(name: "CrowPersistence", dependencies: ["CrowCore"]),
        .testTarget(name: "CrowPersistenceTests", dependencies: ["CrowPersistence"]),
    ]
)
