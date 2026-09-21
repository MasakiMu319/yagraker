import SwiftUI

/// Translation/deep-read streaming and completed result shown inside the popup.
struct PopupGenerationResultView: View {
    @ObservedObject var toolPanel: ToolPanelModel
    let showCopiedFeedback: Bool
    let onCopy: () -> Void
    let onConfigure: () -> Void

    @EnvironmentObject private var l10n: L10n

    var body: some View {
        switch toolPanel.generationPhase {
        case .idle:
            EmptyView()
        case .streaming, .done:
            VStack(alignment: .leading, spacing: 8) {
                statusRow
                StreamingMarkdownView(source: toolPanel.streamSource)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background {
                if TranslationLayoutDiagnostics.isEnabled {
                    TranslationLayoutProbe(
                        streamID: toolPanel.streamSource.id,
                        outputUTF16Count: toolPanel.output.utf16.count,
                        isStreaming: toolPanel.isStreaming
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        case .failed(let message):
            PopupErrorView(message: message, retry: { toolPanel.submit() }, onConfigure: onConfigure)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            if toolPanel.generationPhase == .streaming {
                PulsingStatusIndicator()
                Text(statusTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.fixed)
                Text(statusTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Text("•")
                .font(.system(size: 8))
                .foregroundStyle(Theme.inkSecondary.opacity(0.4))

            Text(toolPanel.selectedProvider.defaultDisplayName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.inkSecondary.opacity(0.7))

            Spacer()

            if toolPanel.generationPhase == .streaming {
                Button(l10n.t("popup.cancel")) {
                    toolPanel.cancelGeneration(clearOutput: false)
                }
                .buttonStyle(CapsuleActionButtonStyle(emphasis: .secondary))
            } else if toolPanel.generationPhase == .done {
                HStack(spacing: 6) {
                    Button {
                        toolPanel.submit()
                    } label: {
                        Label(l10n.t("popup.retry"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(CapsuleActionButtonStyle(emphasis: .secondary))
                    .help(l10n.t("popup.retry"))

                    Button(action: onCopy) {
                        Label(
                            showCopiedFeedback ? l10n.t("translation.copied") : l10n.t("translation.copy"),
                            systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc"
                        )
                        .foregroundStyle(showCopiedFeedback ? Theme.fixed : Theme.onAccent)
                    }
                    .buttonStyle(CapsuleActionButtonStyle(emphasis: showCopiedFeedback ? .secondary : .primary))
                }
            }
        }
        .padding(.bottom, 2)
    }

    private var statusTitle: String {
        let mode = toolPanel.outputMode ?? toolPanel.mode
        switch (mode, toolPanel.generationPhase) {
        case (.translation, .streaming): return l10n.t("translation.translating")
        case (.translation, _): return l10n.t("translation.translated")
        case (.deepRead, .streaming): return l10n.t("translation.deepReading")
        case (.deepRead, _): return l10n.t("translation.deepRead")
        case (.grammar, _): return l10n.t("tool.grammar")
        }
    }
}
