// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrowIPC",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrowIPC", targets: ["CrowIPC"]),
    ],
    targets: [
        .target(name: "CrowIPC"),
    ]
)
