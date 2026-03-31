// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RmProvider",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RmProvider", targets: ["RmProvider"]),
    ],
    dependencies: [
        .package(path: "../RmCore"),
    ],
    targets: [
        .target(name: "RmProvider", dependencies: ["RmCore"]),
    ]
)
