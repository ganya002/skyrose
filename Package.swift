// swift-tools-version: 6.0
import PackageDescription

// SkyRose — Swift Package manifest.
//
// Pure modules (Core, Layout, IPC) build in Swift 6 language mode and are fully
// unit-testable without AppKit. Platform/UI modules build in Swift 5 language
// mode because AppKit/ApplicationServices callbacks are not yet fully annotated
// for strict concurrency; they still compile with the Swift 6 compiler.

let strict: [SwiftSetting] = [.swiftLanguageMode(.v6)]
let relaxed: [SwiftSetting] = [.swiftLanguageMode(.v5), .enableUpcomingFeature("StrictConcurrency")]

let package = Package(
    name: "SkyRose",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CaelestiaCore", targets: ["CaelestiaCore"]),
        .library(name: "CaelestiaLayout", targets: ["CaelestiaLayout"]),
        .library(name: "CaelestiaIPC", targets: ["CaelestiaIPC"]),
        .library(name: "CaelestiaPlatform", targets: ["CaelestiaPlatform"]),
        .library(name: "CaelestiaOverlay", targets: ["CaelestiaOverlay"]),
        .library(name: "CaelestiaShell", targets: ["CaelestiaShell"]),
        .library(name: "CaelestiaServices", targets: ["CaelestiaServices"]),
        .library(name: "CaelestiaWMKit", targets: ["CaelestiaWMKit"]),
        .executable(name: "SkyRoseWM", targets: ["SkyRoseWM"]),
        .executable(name: "skyrose", targets: ["skyrose"]),
        .executable(name: "SkyRoseSettings", targets: ["SkyRoseSettings"]),
        .executable(name: "TestWindows", targets: ["TestWindows"]),
        .executable(name: "gen-keybind-docs", targets: ["gen-keybind-docs"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        // MARK: C shims for private symbols (weak-linked, runtime-checked)
        .target(
            name: "CShims",
            path: "Sources/CShims",
            publicHeadersPath: "include"
        ),

        // MARK: Pure modules
        .target(
            name: "CaelestiaCore",
            dependencies: [.product(name: "TOMLKit", package: "TOMLKit")],
            path: "Sources/CaelestiaCore",
            resources: [.copy("Resources")],
            swiftSettings: strict
        ),
        .target(
            name: "CaelestiaLayout",
            dependencies: ["CaelestiaCore"],
            path: "Sources/CaelestiaLayout",
            swiftSettings: strict
        ),
        .target(
            name: "CaelestiaIPC",
            dependencies: ["CaelestiaCore"],
            path: "Sources/CaelestiaIPC",
            exclude: ["Schema.md"],
            swiftSettings: strict
        ),

        // MARK: Platform modules
        .target(
            name: "CaelestiaPlatform",
            dependencies: ["CaelestiaCore", "CaelestiaLayout", "CShims"],
            path: "Sources/CaelestiaPlatform",
            swiftSettings: relaxed
        ),
        .target(
            name: "CaelestiaServices",
            dependencies: ["CaelestiaCore"],
            path: "Sources/CaelestiaServices",
            resources: [.copy("Resources")],
            swiftSettings: relaxed
        ),
        .target(
            name: "CaelestiaOverlay",
            dependencies: ["CaelestiaCore", "CaelestiaPlatform"],
            path: "Sources/CaelestiaOverlay",
            swiftSettings: relaxed
        ),
        .target(
            name: "CaelestiaShell",
            dependencies: ["CaelestiaCore", "CaelestiaServices"],
            path: "Sources/CaelestiaShell",
            resources: [.copy("Resources")],
            swiftSettings: relaxed
        ),
        .target(
            name: "CaelestiaWMKit",
            dependencies: [
                "CaelestiaCore", "CaelestiaLayout", "CaelestiaIPC",
                "CaelestiaPlatform", "CaelestiaOverlay", "CaelestiaShell", "CaelestiaServices",
            ],
            path: "Sources/CaelestiaWMKit",
            swiftSettings: relaxed
        ),

        // Settings app UI + models (a library so the models are unit-testable).
        .target(
            name: "SkyRoseSettingsKit",
            dependencies: ["CaelestiaCore", "CaelestiaIPC", "CaelestiaPlatform", "CaelestiaShell"],
            path: "Sources/SkyRoseSettingsKit",
            swiftSettings: relaxed
        ),

        // MARK: Executables
        .executableTarget(
            name: "SkyRoseWM",
            dependencies: ["CaelestiaWMKit"],
            path: "Sources/SkyRoseWM",
            swiftSettings: relaxed
        ),
        .executableTarget(
            name: "skyrose",
            dependencies: ["CaelestiaCore", "CaelestiaIPC"],
            path: "Sources/skyrose",
            swiftSettings: relaxed
        ),
        // SkyRose Settings + onboarding (SwiftUI app; talks to the WM over IPC).
        .executableTarget(
            name: "SkyRoseSettings",
            dependencies: ["SkyRoseSettingsKit"],
            path: "Sources/SkyRoseSettings",
            swiftSettings: relaxed
        ),
        .executableTarget(
            name: "TestWindows",
            dependencies: [],
            path: "Sources/TestWindows",
            swiftSettings: relaxed
        ),
        .executableTarget(
            name: "gen-keybind-docs",
            dependencies: ["CaelestiaCore"],
            path: "Tools/gen-keybind-docs",
            swiftSettings: relaxed
        ),

        // MARK: Tests
        .testTarget(
            name: "CaelestiaCoreTests",
            dependencies: ["CaelestiaCore"],
            path: "Tests/CaelestiaCoreTests",
            swiftSettings: strict
        ),
        .testTarget(
            name: "CaelestiaLayoutTests",
            dependencies: ["CaelestiaLayout", "CaelestiaCore"],
            path: "Tests/CaelestiaLayoutTests",
            swiftSettings: strict
        ),
        .testTarget(
            name: "CaelestiaIPCTests",
            dependencies: ["CaelestiaIPC"],
            path: "Tests/CaelestiaIPCTests",
            swiftSettings: strict
        ),
        .testTarget(
            name: "CaelestiaPlatformTests",
            dependencies: ["CaelestiaPlatform"],
            path: "Tests/CaelestiaPlatformTests",
            swiftSettings: relaxed
        ),
        .testTarget(
            name: "CaelestiaServicesTests",
            dependencies: ["CaelestiaServices"],
            path: "Tests/CaelestiaServicesTests",
            swiftSettings: relaxed
        ),
        .testTarget(
            name: "CaelestiaOverlayTests",
            dependencies: ["CaelestiaOverlay"],
            path: "Tests/CaelestiaOverlayTests",
            swiftSettings: relaxed
        ),
        .testTarget(
            name: "CaelestiaWMKitTests",
            dependencies: ["CaelestiaWMKit", "CaelestiaPlatform", "CaelestiaLayout", "CaelestiaIPC", "CaelestiaCore", "CaelestiaOverlay"],
            path: "Tests/CaelestiaWMKitTests",
            swiftSettings: relaxed
        ),
        .testTarget(
            name: "SkyRoseSettingsTests",
            dependencies: ["SkyRoseSettingsKit", "CaelestiaCore", "CaelestiaIPC"],
            path: "Tests/SkyRoseSettingsTests",
            swiftSettings: relaxed
        ),
        .testTarget(
            name: "CaelestiaShellTests",
            dependencies: ["CaelestiaShell"],
            path: "Tests/CaelestiaShellTests",
            swiftSettings: relaxed
        ),
    ]
)
