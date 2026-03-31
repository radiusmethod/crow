// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RmPersistence",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RmPersistence", targets: ["RmPersistence"]),
    ],
    dependencies: [
        .package(path: "../RmCore"),
    ],
    targets: [
        .target(name: "RmPersistence", dependencies: ["RmCore"]),
    ]
)
