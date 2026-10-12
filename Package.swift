// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IPTVPlayer",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Prebuilt static libmpv + FFmpeg (LGPL), universal, macOS 12+. Statically linked, so the
        // app runs on other Macs without Homebrew.
        .package(url: "https://github.com/mpvkit/MPVKit.git", exact: "1.0.0"),
        // Auto-updates. Sparkle.framework is dynamic: build-app.sh embeds it in Contents/Frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "IPTVPlayer",
            dependencies: [
                .product(name: "MPVKit", package: "MPVKit"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/IPTVPlayer",
            swiftSettings: [.unsafeFlags(["-Xcc", "-DGL_SILENCE_DEPRECATION"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ],
    swiftLanguageModes: [.v5]
)
