import AppKit
import SwiftUI

/// Four-pane settings surface.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var l10n: L10n
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTab: SettingsTab = .general
    @State private var accessibilityGranted = SelectionReader.isAccessibilityGranted

    @StateObject private var viewModel = SettingsViewModel()
    @State private var isAPIKeyVisible = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selectedTab: $selectedTab)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Group {
                switch selectedTab {
                case .general: generalPane
                case .provider: providerPane
                case .shortcuts: shortcutsPane
                case .about: aboutPane
                }
            }
            .id(selectedTab)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selectedTab)
        }
        .frame(width: 620, height: 520)
        .background(Theme.paper)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = SelectionReader.isAccessibilityGranted
        }
    }

    private var generalPane: some View {
        SettingsGeneralPane(accessibilityGranted: accessibilityGranted) {
            accessibilityGranted = SelectionReader.promptForAccessibilityIfNeeded()
            if !accessibilityGranted,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: Provider

    private var providerPane: some View {
        SettingsProviderPane(
            viewModel: viewModel,
            isAPIKeyVisible: $isAPIKeyVisible,
            refreshConfiguration: { appState.toolPanelModel.refreshConfiguration() }
        )
    }

    private var shortcutsPane: some View {
        SettingsShortcutsPane()
    }

    private var aboutPane: some View {
        SettingsAboutPane()
    }

}