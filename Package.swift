// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudePet",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "ClaudePetCore",
            path: "Sources/ClaudePetCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ClaudePet",
            dependencies: ["ClaudePetCore"],
            path: "Sources/ClaudePet",
            // Keep the app in Swift 5 mode: it predates Swift 6 strict
            // concurrency checking and AppKit/SwiftUI call sites throughout
            // (NSPanel, ObservableObject stores) aren't annotated for it.
            // Bumping this is future work, not a side effect of adding tests.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClaudePetCoreTests",
            dependencies: ["ClaudePetCore"],
            path: "Tests/ClaudePetCoreTests"
        ),
    ]
)
