// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NotchApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchApp", targets: ["NotchApp"]),
        .library(name: "NowPlayingHelper", type: .dynamic, targets: ["NowPlayingHelper"]),
    ],
    targets: [
        .executableTarget(
            name: "NotchApp",
            path: "Sources/NotchApp"
        ),
        // Loaded into /usr/bin/perl at runtime; see Resources/nowplaying.pl.
        .target(
            name: "NowPlayingHelper",
            path: "Sources/NowPlayingHelper",
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("AppKit")]
        ),
    ]
)
