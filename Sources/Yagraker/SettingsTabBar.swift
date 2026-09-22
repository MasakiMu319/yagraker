import AppKit
import SwiftUI

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
        // Single persistent selection pill behind the labels, gliding via an
        // animated offset (see `LiquidGlassPill` for why this is not a
        // `glassEffectID` morph).
        ZStack(alignment: .leading) {
            LiquidGlassPill(tint: Theme.accentSoft)
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
