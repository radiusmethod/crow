// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RmCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RmCore", targets: ["RmCore"]),
    ],
    targets: [
        .target(name: "RmCore"),
        .testTarget(name: "RmCoreTests", dependencies: ["RmCore"]),
    ]
)
