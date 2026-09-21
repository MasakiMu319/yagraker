import AppKit
import Combine
import SwiftUI
import YagrakerCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, provider, shortcuts, about
    var id: String { rawValue }

    var icon: Image {
        Image(nsImage: iconImage)
    }

    private var iconImage: NSImage {
        switch self {
        case .general: return ReIconAsset.settings
        case .provider: return ReIconAsset.sparkles
        case .shortcuts: return ReIconAsset.keyboard
        case .about: return ReIconAsset.infoCircle
        }
    }

    @MainActor
    func title(_ l10n: L10n) -> String {
        l10n.t("settings.tab.\(rawValue)")
    }
}

struct SettingsTabBar: View {
    private static let segmentWidth: CGFloat = 112
    private static let segmentHeight: CGFloat = 54
    private static let selectionWidth: CGFloat = 104
    private static let selectionHeight: CGFloat = 48

    @EnvironmentObject private var l10n: L10n
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTab: SettingsTab

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.accentSoft)
                .frame(width: Self.selectionWidth, height: Self.selectionHeight)
                .offset(x: selectionOffset)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    let selected = selectedTab == tab
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 3) {
                            tab.icon
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .accessibilityHidden(true)
                            Text(tab.title(l10n))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(selected ? Theme.accent : Theme.inkSecondary)
                        .frame(width: Self.segmentWidth, height: Self.segmentHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CapsuleSegmentButtonStyle(isSelected: selected))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .frame(
            width: Self.segmentWidth * CGFloat(SettingsTab.allCases.count),
            height: Self.segmentHeight
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: selectedTab)
    }

    private var selectionOffset: CGFloat {
        let index = SettingsTab.allCases.firstIndex(of: selectedTab)!
        return CGFloat(index) * Self.segmentWidth + (Self.segmentWidth - Self.selectionWidth) / 2
    }
}

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