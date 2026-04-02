// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrowTerminal",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrowTerminal", targets: ["CrowTerminal"]),
    ],
    targets: [
        .target(
            name: "CrowTerminal",
            dependencies: ["GhosttyKit"],
            swiftSettings: [
                .unsafeFlags(["-I../../Frameworks/GhosttyKit.xcframework/macos-arm64/Headers"]),
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreText"),
                .linkedFramework("IOSurface"),
                .linkedLibrary("c++"),
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "../../Frameworks/GhosttyKit.xcframework"
        ),
    ]
)
