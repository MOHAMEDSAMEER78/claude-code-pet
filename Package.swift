// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudePet",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Auto-update only - independent of Apple code signing/notarization.
        // Sparkle verifies update packages with its own EdDSA keypair (see
        // SUPublicEDKey in Info.plist), not Gatekeeper.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "ClaudePetCore",
            path: "Sources/ClaudePetCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ClaudePet",
            dependencies: [
                "ClaudePetCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/ClaudePet",
            resources: [.process("Resources")],
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
