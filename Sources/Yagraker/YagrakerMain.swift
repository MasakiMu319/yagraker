import AppKit

/// Pure AppKit entry point (no SwiftUI.App lifecycle): LSUIElement menu-bar app.
@MainActor
@main
enum YagrakerMain {
    private static let appDelegate = YagrakerAppDelegate()
    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory) // LSUIElement: menu bar only, no Dock icon
        MainMenuController.shared.install()
        app.run()
    }
}
