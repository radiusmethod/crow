// swift-tools-version: 6.0
import PackageDescription
import Foundation

// CROW-466 spike: mirror the CrowTerminal-side flag so the app target's
// AppDelegate forks resolve to the right renderer at compile time.
let useSwiftTerm = ProcessInfo.processInfo.environment["CROW_RENDERER_SWIFTTERM"] != nil
let appSwiftSettings: [SwiftSetting] = useSwiftTerm ? [.define("CROW_RENDERER_SWIFTTERM")] : []

let package = Package(
    name: "Crow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CrowApp", targets: ["Crow"]),
        .executable(name: "crow", targets: ["CrowCLI"]),
    ],
    dependencies: [
        .package(path: "Packages/CrowCore"),
        .package(path: "Packages/CrowUI"),
        .package(path: "Packages/CrowTerminal"),
        .package(path: "Packages/CrowGit"),
        .package(path: "Packages/CrowProvider"),
        .package(path: "Packages/CrowPersistence"),
        .package(path: "Packages/CrowClaude"),
        .package(path: "Packages/CrowCodex"),
        .package(path: "Packages/CrowCursor"),
        .package(path: "Packages/CrowIPC"),
        .package(path: "Packages/CrowTelemetry"),
        .package(path: "Packages/CrowCLI"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "Crow",
            dependencies: [
                "CrowCore",
                "CrowUI",
                "CrowTerminal",
                "CrowGit",
                "CrowProvider",
                "CrowPersistence",
                "CrowClaude",
                "CrowCodex",
                "CrowCursor",
                "CrowIPC",
                "CrowTelemetry",
            ],
            path: "Sources/Crow",
            resources: [
                .copy("Resources/AppIcon.png"),
                .copy("Resources/CorveilBrandmark.svg"),
            ],
            swiftSettings: appSwiftSettings,
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
            name: "CrowCLI",
            dependencies: [
                .product(name: "CrowCLILib", package: "CrowCLI"),
            ],
            path: "Sources/CrowCLI"
        ),
        .testTarget(
            name: "CrowTests",
            dependencies: ["Crow"],
            path: "Tests/CrowTests"
        ),
    ]
)
