import SwiftUI
import YagrakerCore

/// Grammar correction result shown inside the popup.
struct PopupGrammarResultView: View {
    let result: CorrectionResult
    let originalText: String
    let showCopiedFeedback: Bool
    let onAccept: () -> Void
    let onRetry: () -> Void
    let onCopy: () -> Void

    @EnvironmentObject private var l10n: L10n
    @State private var viewMode = ViewMode.diff

    private enum ViewMode: String, CaseIterable {
        case diff
        case preview
    }

    var body: some View {
        if result.hasCorrections {
            correctedSection
            if result.hasExplanations {
                explanationsSection(result.corrections)
            }
            if !result.tip.isEmpty {
                analysisSection(l10n.t("popup.goodToKnow"), text: result.tip)
            }
            actionRow
        } else {
            perfectView
        }
    }

    private var correctedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l10n.t("popup.corrected"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .textCase(.uppercase)

                Spacer()

                HStack(spacing: 2) {
                    modeButton(mode: .diff, title: l10n.t("popup.diff"))
                    modeButton(mode: .preview, title: l10n.t("popup.preview"))
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.cardSubtle)
                )
            }

            Group {
                if viewMode == .diff {
                    SegmentedTextView(originalText: originalText, corrections: result.corrections)
                } else {
                    Text(result.splicingCorrections(into: originalText) ?? originalText)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.resultCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func modeButton(mode: ViewMode, title: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                viewMode = mode
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: viewMode == mode ? .semibold : .medium))
                .foregroundStyle(viewMode == mode ? Theme.ink : Theme.inkSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(viewMode == mode ? Theme.card : Color.clear)
                        .shadow(color: viewMode == mode ? Color.black.opacity(0.06) : Color.clear, radius: 1, x: 0, y: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func explanationsSection(_ corrections: [Correction]) -> some View {
        let items = corrections.filter {
            if let exp = $0.explanation, !exp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            return false
        }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                    Text(l10n.t("popup.explanations"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .textCase(.uppercase)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.original)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .strikethrough()
                                    .foregroundStyle(Theme.wrong)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.inkSecondary.opacity(0.6))
                                Text(item.corrected)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.fixed)
                            }
                            if let explanation = item.explanation, !explanation.isEmpty {
                                Text(LocalizedStringKey(explanation))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if item.id != items.last?.id {
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 0.5)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.resultCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private var perfectView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.fixed)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t("popup.looksGreat"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(l10n.t("popup.noIssues"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func analysisSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .textCase(.uppercase)
            }
            Text(LocalizedStringKey(text))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.resultCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
        )
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                onAccept()
            } label: {
                Label(l10n.t("popup.accept"), systemImage: "checkmark")
            }
            .buttonStyle(CapsuleActionButtonStyle(emphasis: .primary))

            Button(l10n.t("popup.retry"), action: onRetry)
                .buttonStyle(CapsuleActionButtonStyle(emphasis: .secondary))

            Button {
                onCopy()
            } label: {
                Label(
                    showCopiedFeedback ? l10n.t("popup.copied") : l10n.t("popup.copy"),
                    systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(CapsuleActionButtonStyle(emphasis: .secondary))

            Spacer()
        }
    }
}
