import AppKit
import SwiftUI

/// Owns the single reusable Settings window.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private weak var appState: AppState?
    private var languageObserver: NSObjectProtocol?
    private var hasCentered = false

    init(appState: AppState) {
        self.appState = appState
        let root = SettingsView()
            .environmentObject(appState)
            .environmentObject(L10n.shared)
        let hostingView = NSHostingView(rootView: root)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.title = L10n.shared.t("settings.title")
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.paper)

        super.init()
        window.delegate = self
        languageObserver = NotificationCenter.default.addObserver(
            forName: L10n.languageChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.window.title = L10n.shared.t("settings.title")
            }
        }
    }

    deinit {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
    }

    func show() {
        if !hasCentered {
            window.center()
            hasCentered = true
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        appState?.restoreExternalApplicationIfNeeded()
    }
}
