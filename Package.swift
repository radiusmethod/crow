// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RmAiIde",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RmAiIde", targets: ["RmAiIde"]),
        .executable(name: "ride", targets: ["RmIdeCLI"]),
    ],
    dependencies: [
        .package(path: "Packages/RmCore"),
        .package(path: "Packages/RmUI"),
        .package(path: "Packages/RmTerminal"),
        .package(path: "Packages/RmGit"),
        .package(path: "Packages/RmProvider"),
        .package(path: "Packages/RmPersistence"),
        .package(path: "Packages/RmClaude"),
        .package(path: "Packages/RmIPC"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "RmAiIde",
            dependencies: [
                "RmCore",
                "RmUI",
                "RmTerminal",
                "RmGit",
                "RmProvider",
                "RmPersistence",
                "RmClaude",
                "RmIPC",
            ],
            path: "Sources/RmAiIde",
            resources: [
                .copy("Resources/AppIcon.png"),
                .copy("Resources/CorveilBrandmark.png"),
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreText"),
                .linkedFramework("IOSurface"),
                .linkedFramework("UserNotifications"),
                .linkedLibrary("c++"),
                .unsafeFlags(["-Xlinker", "-ld_classic"]),
            ]
        ),
        .executableTarget(
            name: "RmIdeCLI",
            dependencies: [
                "RmIPC",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/RmIdeCLI"
        ),
    ]
)
