// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Yagraker",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Yagraker", targets: ["Yagraker"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/Lakr233/MarkdownView", from: "4.1.0"),
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
                .product(name: "MarkdownView", package: "MarkdownView"),
                .product(name: "MarkdownParser", package: "MarkdownView"),
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
