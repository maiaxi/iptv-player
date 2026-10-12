// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IPTVPlayer",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Prebuilt static libmpv + FFmpeg (LGPL), universal, macOS 12+. Statically linked, so the
        // app runs on other Macs without Homebrew.
        .package(url: "https://github.com/mpvkit/MPVKit.git", exact: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "IPTVPlayer",
            dependencies: [.product(name: "MPVKit", package: "MPVKit")],
            path: "Sources/IPTVPlayer",
            swiftSettings: [.unsafeFlags(["-Xcc", "-DGL_SILENCE_DEPRECATION"])]
        ),
    ],
    swiftLanguageModes: [.v5]
)
