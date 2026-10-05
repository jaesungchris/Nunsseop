// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Nunsseop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Nunsseop", targets: ["Nunsseop"]),
        .library(name: "NowPlayingHelper", type: .dynamic, targets: ["NowPlayingHelper"]),
    ],
    targets: [
        .executableTarget(
            name: "Nunsseop",
            path: "Sources/Nunsseop"
        ),
        // Loaded into /usr/bin/perl at runtime; see Resources/nowplaying.pl.
        .target(
            name: "NowPlayingHelper",
            path: "Sources/NowPlayingHelper",
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("AppKit")]
        ),
        .testTarget(
            name: "NunsseopTests",
            dependencies: ["Nunsseop"],
            path: "Tests/NunsseopTests"
        ),
    ]
)
