// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RmGit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RmGit", targets: ["RmGit"]),
    ],
    dependencies: [
        .package(path: "../RmCore"),
    ],
    targets: [
        .target(name: "RmGit", dependencies: ["RmCore"]),
    ]
)
