// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Yagraker",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Yagraker", targets: ["Yagraker"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/microsoft/SwiftStreamingMarkdown", revision: "95bb755a9b23a1aea8682b9ebc912cb72b176c95"),
    ],
    targets: [
        // Pure logic: models, prompts, LLM services, persistence. Unit-testable.
        .target(
            name: "YagrakerCore",
            path: "Sources/YagrakerCore"
        ),
        // App: AppKit windowing + SwiftUI views.
        .executableTarget(
            name: "Yagraker",
            dependencies: [
                "YagrakerCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "SwiftStreamingMarkdown", package: "SwiftStreamingMarkdown"),
            ],
            path: "Sources/Yagraker",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "YagrakerCoreTests",
            dependencies: ["YagrakerCore"],
            path: "Tests/YagrakerCoreTests"
        ),
        .testTarget(
            name: "YagrakerUITests",
            dependencies: [
                "Yagraker",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Tests/YagrakerUITests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
