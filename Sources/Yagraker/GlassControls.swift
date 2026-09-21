import SwiftUI
import YagrakerCore


struct GlassModeSelector: View {
    @EnvironmentObject private var l10n: L10n
    let selectedMode: ToolPanelModel.Mode
    let onSelect: (ToolPanelModel.Mode) -> Void
    @Namespace private var selectionIndicator

    private static let segmentWidth: CGFloat = 73

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ToolPanelModel.Mode.allCases, id: \.self) { mode in
                let selected = selectedMode == mode
                Button {
                    onSelect(mode)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .medium))
                        Text(mode.title(l10n))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSecondary)
                    .padding(.horizontal, 5)
                    .frame(width: Self.segmentWidth, height: 34)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.accentSoft)
                                .matchedGeometryEffect(id: "mode-selection", in: selectionIndicator)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(CapsuleSegmentButtonStyle(isSelected: selected))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.ink.opacity(0.06)))
        .fixedSize(horizontal: true, vertical: false)
        .animation(.spring(response: 0.22, dampingFraction: 0.86), value: selectedMode)
    }
}

// MARK: - Provider picker

struct GlassProviderPicker: View {
    @ObservedObject var model: ToolPanelModel
    @EnvironmentObject private var l10n: L10n

    private func displayName(_ kind: LLMProviderKind) -> String {
        switch kind {
        case .gemini: return "Gemini"
        case .qwen: return "Qwen"
        case .mimo: return "MiMo"
        case .deepseek: return "DeepSeek"
        case .custom: return l10n.t("provider.custom") == "provider.custom" ? "Custom" : l10n.t("provider.custom")
        }
    }

    var body: some View {
        Menu {
            Picker("", selection: $model.selectedProvider) {
                ForEach(model.configuredProviders) { kind in
                    Label {
                        Text(displayName(kind))
                    } icon: {
                        ProviderIcon(provider: kind)
                    }
                    .tag(kind)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 5) {
                ProviderIcon(provider: model.selectedProvider, size: 12)
                Text(displayName(model.selectedProvider))
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .opacity(0.65)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: 28)
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 9)
            .contentShape(Capsule())
            .background(
                Capsule()
                    .fill(Theme.ink.opacity(0.05))
                    .overlay(
                        Capsule()
                            .strokeBorder(Theme.cardBorder, lineWidth: 0.6)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.configuredProviders.isEmpty)
    }
}

// MARK: - SF Symbol wrapper

struct SystemSymbolIcon: View {
    let name: String
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .medium))
    }
}


// MARK: - Pulsing status dot

struct PulsingStatusIndicator: View {
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(isPulsing ? 0.22 : 0.6))
                .frame(width: 12, height: 12)
                .scaleEffect(isPulsing ? 1.35 : 0.75)
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
