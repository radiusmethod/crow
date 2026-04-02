// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrowGit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrowGit", targets: ["CrowGit"]),
    ],
    dependencies: [
        .package(path: "../CrowCore"),
    ],
    targets: [
        .target(name: "CrowGit", dependencies: ["CrowCore"]),
    ]
)
