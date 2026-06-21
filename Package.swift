// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppReset",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "AppResetKit", targets: ["AppResetKit"]),
        .executable(name: "appreset", targets: ["appreset"]),
        .executable(name: "AppResetApp", targets: ["AppResetApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Shared core: app discovery, TCC reading, data scanning, reset engine.
        // Foundation + SQLite3 only — no UI, no ArgumentParser — so both front-ends share it.
        .target(
            name: "AppResetKit",
            path: "Sources/AppResetKit",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),

        // Scriptable CLI. Binary: `appreset`.
        .executableTarget(
            name: "appreset",
            dependencies: [
                "AppResetKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CLI"
        ),

        // SwiftUI app. Binary: `AppResetApp` (packaged into AppReset.app).
        .executableTarget(
            name: "AppResetApp",
            dependencies: ["AppResetKit"],
            path: "Sources/App"
        ),

        .testTarget(
            name: "AppResetKitTests",
            dependencies: ["AppResetKit"],
            path: "Tests/AppResetKitTests"
        ),
    ]
)
