// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RmUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RmUI", targets: ["RmUI"]),
    ],
    dependencies: [
        .package(path: "../RmCore"),
        .package(path: "../RmTerminal"),
    ],
    targets: [
        .target(name: "RmUI", dependencies: ["RmCore", "RmTerminal"]),
    ]
)
