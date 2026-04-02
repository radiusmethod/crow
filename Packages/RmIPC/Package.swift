// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RmIPC",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RmIPC", targets: ["RmIPC"]),
    ],
    targets: [
        .target(name: "RmIPC"),
    ]
)
