// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppReset",
    // Required by the vendored PermissionFlow localized .strings resources.
    defaultLocalization: "en",
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
            dependencies: [
                "AppResetKit",
                // Vendored PermissionFlow — powers AppReset's own permissions panel.
                "PermissionFlow",
                "SystemSettingsKit",
                "PermissionFlowStatusStore",
                "PermissionFlowExtendedStatus",
            ],
            path: "Sources/App"
        ),

        // MARK: - Vendored PermissionFlow ------------------------------------
        // Source copied into this repo from github.com/jaywcjlove/PermissionFlow
        // (MIT) — built as local targets, NOT linked as an external/remote
        // package — so AppReset can check its own permission status (Full Disk
        // Access, etc.) and show drag-to-grant guidance into System Settings.
        .target(
            name: "SystemSettingsKit",
            path: "Sources/SystemSettingsKit"
        ),
        .target(
            name: "PermissionFlow",
            dependencies: ["SystemSettingsKit"],
            path: "Sources/PermissionFlow",
            resources: [.process("Resources")]
        ),
        .target(
            name: "PermissionFlowStatusStore",
            dependencies: ["PermissionFlow"],
            path: "Sources/PermissionFlowStatusStore"
        ),
        .target(
            name: "PermissionFlowBluetoothStatus",
            dependencies: ["PermissionFlow"],
            path: "Sources/PermissionFlowBluetoothStatus"
        ),
        .target(
            name: "PermissionFlowMediaStatus",
            dependencies: ["PermissionFlow"],
            path: "Sources/PermissionFlowMediaStatus"
        ),
        .target(
            name: "PermissionFlowInputMonitoringStatus",
            dependencies: ["PermissionFlow"],
            path: "Sources/PermissionFlowInputMonitoringStatus"
        ),
        .target(
            name: "PermissionFlowScreenRecordingStatus",
            dependencies: ["PermissionFlow"],
            path: "Sources/PermissionFlowScreenRecordingStatus"
        ),
        .target(
            name: "PermissionFlowExtendedStatus",
            dependencies: [
                "PermissionFlowBluetoothStatus",
                "PermissionFlowMediaStatus",
                "PermissionFlowInputMonitoringStatus",
                "PermissionFlowScreenRecordingStatus",
            ],
            path: "Sources/PermissionFlowExtendedStatus"
        ),

        .testTarget(
            name: "AppResetKitTests",
            dependencies: ["AppResetKit"],
            path: "Tests/AppResetKitTests"
        ),
    ]
)
