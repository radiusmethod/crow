// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrowTerminal",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrowTerminal", targets: ["CrowTerminal"]),
    ],
    dependencies: [
        .package(path: "../CrowCore"),
    ],
    targets: [
        .target(
            name: "CrowTerminal",
            dependencies: [
                "GhosttyKit",
                .product(name: "CrowCore", package: "CrowCore"),
            ],
            resources: [
                .copy("Resources/crow-shell-wrapper.sh"),
                .copy("Resources/crow-tmux.conf"),
            ],
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
        .testTarget(
            name: "CrowTerminalTests",
            dependencies: ["CrowTerminal"]
        ),
    ]
)
