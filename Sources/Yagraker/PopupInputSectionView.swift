import SwiftUI

/// Full or compact source-text editor shown above popup results.
struct PopupInputSectionView: View {
    @ObservedObject var toolPanel: ToolPanelModel
    @ObservedObject var grammar: GrammarCoordinator
    let panelHeight: CGFloat

    @EnvironmentObject private var l10n: L10n

    var body: some View {
        if toolPanel.mode == .grammar && grammar.isLoading {
            EmptyView()
        } else if toolPanel.mode == .grammar, grammar.correctionResult != nil {
            compactSourceSection
        } else if toolPanel.mode == .grammar {
            fullInputSection(isGrammar: true)
        } else if toolPanel.outputMode == toolPanel.mode,
                  (toolPanel.isStreaming || toolPanel.hasOutput) {
            compactSourceSection
        } else {
            fullInputSection(isGrammar: false)
        }
    }

    /// Full input card used before generation / grammar check starts.
    private func fullInputSection(isGrammar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            QuickTranslationTextEditor(
                text: $toolPanel.input,
                placeholder: l10n.t("popup.textToProcess"),
                minHeight: 96,
                maxHeight: isGrammar ? 96 : idleEditorMaxHeight,
                onSubmit: { toolPanel.submit() },
                onPasteAndSubmit: {
                    DispatchQueue.main.async { toolPanel.submit() }
                }
            )
            .padding(.horizontal, 10)
            .padding(.top, 10)

            HStack(spacing: 8) {
                if !toolPanel.input.isEmpty {
                    Button {
                        toolPanel.input = ""
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10.5))
                            Text(l10n.t("common.clear"))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Theme.inkSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.t("common.clear"))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Text(shortcutHintText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkSecondary.opacity(0.6))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if !toolPanel.input.isEmpty {
                    Text("\(toolPanel.input.count)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.inkSecondary.opacity(0.55))
                        .transition(.opacity)
                }

                submitButton(title: isGrammar ? l10n.t("popup.actionGrammar") : translateActionTitle)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 0.8)
        )
    }

    /// Compact source view shown once results are active, keeping original visible and editable.
    private var compactSourceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            originalLabel

            QuickTranslationTextEditor(
                text: $toolPanel.input,
                placeholder: l10n.t("popup.textToProcess"),
                minHeight: 32,
                maxHeight: sourceEditorMaxHeight,
                onSubmit: { toolPanel.submit() },
                onPasteAndSubmit: {
                    DispatchQueue.main.async { toolPanel.submit() }
                }
            )
        }
    }

    private var originalLabel: some View {
        Text(l10n.t("popup.original"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.inkSecondary)
            .textCase(.uppercase)
    }

    private var shortcutHintText: String {
        switch toolPanel.mode {
        case .translation: return l10n.t("popup.hintTranslate")
        case .grammar: return l10n.t("popup.hintGrammar")
        case .deepRead: return l10n.t("popup.hintDeepRead")
        }
    }

    private var translateActionTitle: String {
        switch toolPanel.mode {
        case .translation: return l10n.t("popup.actionTranslate")
        case .deepRead: return l10n.t("popup.actionDeepRead")
        case .grammar: return l10n.t("popup.actionGrammar")
        }
    }

    private func submitButton(title: String) -> some View {
        Button {
            toolPanel.submit()
        } label: {
            Image(systemName: "arrow.up")
        }
        .buttonStyle(CircleActionButtonStyle())
        .disabled(
            (toolPanel.mode != .grammar && toolPanel.isStreaming)
                || toolPanel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        .help(title)
        .accessibilityLabel(title)
    }

    private var idleEditorMaxHeight: CGFloat {
        min(max(96, panelHeight * 0.45), 280)
    }

    private var sourceEditorMaxHeight: CGFloat {
        min(max(72, panelHeight * 0.3), 240)
    }
}
