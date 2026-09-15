import SwiftUI
import MarkdownView
import YagrakerCore

/// The popup panel content: mode/provider header, input area, result area,
/// and action buttons.
struct PopupView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var toolPanel: ToolPanelModel
    @EnvironmentObject private var l10n: L10n
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showCopiedFeedback = false
    @State private var copyFeedbackID = UUID()
    @State private var grammarViewMode = GrammarViewMode.diff

    private enum GrammarViewMode: String, CaseIterable {
        case diff
        case preview
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    inputSection
                    if hasResultArea {
                        if toolPanel.mode == .grammar, !appState.grammar.isLoading {
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 1)
                        }
                        resultArea
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .id("\(toolPanel.mode.rawValue)-\(toolPanel.streamSource.id)")

            if let notice = appState.grammar.replacedNotice {
                noticeBanner(notice)
            }

            WindowResizeHandle()
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.paper.opacity(0.94))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 0.8)
        )
        .onChange(of: toolPanel.output) { _, _ in
            if appState.popupWindow.isVisible, !toolPanel.isStreaming {
                // Resize only once streaming ends. During streaming the outer
                // ScrollView grows its document while the window frame stays put.
                appState.popupWindow.scheduleHeightSettle()
            }
        }
        .onChange(of: toolPanel.generationPhase) { _, _ in
            if appState.popupWindow.isVisible {
                appState.popupWindow.scheduleHeightSettle(animated: !toolPanel.isStreaming)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 7) {
            Button {
                appState.togglePin()
            } label: {
                SystemSymbolIcon(name: appState.isPinned ? "pin.fill" : "pin", size: 12)
                    .foregroundStyle(appState.isPinned ? Theme.accent : Theme.inkSecondary)
                    .rotationEffect(.degrees(appState.isPinned ? 0 : -45))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: appState.isPinned)
            }
            .buttonStyle(.ghost)
            .help(appState.isPinned ? l10n.t("popup.unpin") : l10n.t("popup.pin"))
            .accessibilityLabel(appState.isPinned ? l10n.t("popup.unpin") : l10n.t("popup.pin"))

            GlassModeSelector(selectedMode: toolPanel.mode, onSelect: toolPanel.selectMode)

            Spacer(minLength: 12)

            GlassProviderPicker(model: toolPanel)

            Button {
                appState.dismissPopup()
            } label: {
                SystemSymbolIcon(name: "xmark", size: 11)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .buttonStyle(.ghost)
            .help(l10n.t("common.close"))
            .accessibilityLabel(l10n.t("common.close"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            WindowDragHandle(
                onChanged: { appState.popupWindow.moveManually(by: $0) },
                onEnded: { appState.popupWindow.endManualMove() }
            )
        )
    }

    // MARK: Input

    @ViewBuilder
    private var inputSection: some View {
        if toolPanel.mode == .grammar && appState.grammar.isLoading {
            EmptyView()
        } else if toolPanel.mode == .grammar, appState.grammar.correctionResult != nil {
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
        min(max(96, appState.panelHeight * 0.45), 280)
    }

    private var sourceEditorMaxHeight: CGFloat {
        min(max(72, appState.panelHeight * 0.3), 240)
    }

    // MARK: Results

    private var originalLabel: some View {
        Text(l10n.t("popup.original"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.inkSecondary)
            .textCase(.uppercase)
    }

    private var hasResultArea: Bool {
        (toolPanel.mode == .grammar && appState.grammar.isLoading)
            || appState.grammar.errorMessage != nil
            || (toolPanel.mode == .grammar && appState.grammar.correctionResult != nil)
            || (toolPanel.outputMode == toolPanel.mode && toolPanel.generationPhase != .idle)
    }

    @ViewBuilder
    private var resultArea: some View {
        if let error = appState.grammar.errorMessage {
            errorView(error, retry: toolPanel.mode == .grammar ? { appState.retry() } : nil)
        } else if toolPanel.mode == .grammar, appState.grammar.isLoading {
            TextScanLoadingView(text: appState.grammar.originalText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else if let result = appState.grammar.correctionResult, toolPanel.mode == .grammar {
            grammarResult(result)
        } else if toolPanel.outputMode == toolPanel.mode,
                  (toolPanel.mode == .translation || toolPanel.mode == .deepRead) {
            generationResult
        }
    }

    // MARK: Grammar result

    @ViewBuilder
    private func grammarResult(_ result: CorrectionResult) -> some View {
        if result.hasCorrections {
            correctedSection(result)
            if result.hasExplanations {
                explanationsSection(result.corrections)
            }
            if !result.tip.isEmpty {
                analysisSection(l10n.t("popup.goodToKnow"), text: result.tip)
            }
            actionRow(
                primary: (l10n.t("popup.accept"), "checkmark", { appState.replaceOriginalText() }),
                showRetry: true
            )
        } else {
            perfectView
        }
    }

    private func correctedSection(_ result: CorrectionResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l10n.t("popup.corrected"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .textCase(.uppercase)

                Spacer()

                HStack(spacing: 2) {
                    grammarModeButton(mode: .diff, title: l10n.t("popup.diff"))
                    grammarModeButton(mode: .preview, title: l10n.t("popup.preview"))
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.cardSubtle)
                )
            }

            Group {
                if grammarViewMode == .diff {
                    SegmentedTextView(originalText: appState.grammar.originalText, corrections: result.corrections)
                } else {
                    Text(result.splicingCorrections(into: appState.grammar.originalText) ?? appState.grammar.originalText)
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
                    .fill(Theme.fixedSoft)
            )
        }
    }

    private func grammarModeButton(mode: GrammarViewMode, title: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                grammarViewMode = mode
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: grammarViewMode == mode ? .semibold : .medium))
                .foregroundStyle(grammarViewMode == mode ? Theme.ink : Theme.inkSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(grammarViewMode == mode ? Theme.card : Color.clear)
                        .shadow(color: grammarViewMode == mode ? Color.black.opacity(0.06) : Color.clear, radius: 1, x: 0, y: 0.5)
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
                    .fill(Theme.cardSubtle)
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
                .fill(Theme.cardSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: Translation result

    @ViewBuilder
    private var generationResult: some View {
        switch toolPanel.generationPhase {
        case .idle:
            EmptyView()
        case .streaming, .done:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if toolPanel.generationPhase == .streaming {
                        PulsingStatusIndicator()
                        Text(generationStatusTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.fixed)
                        Text(generationStatusTitle)
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

                            Button {
                                toolPanel.copyOutput()
                                showCopyFeedback()
                            } label: {
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
            errorView(message, retry: { toolPanel.submit() })
        }
    }

    private var generationStatusTitle: String {
        let mode = toolPanel.outputMode ?? toolPanel.mode
        switch (mode, toolPanel.generationPhase) {
        case (.translation, .streaming): return l10n.t("translation.translating")
        case (.translation, _): return l10n.t("translation.translated")
        case (.deepRead, .streaming): return l10n.t("translation.deepReading")
        case (.deepRead, _): return l10n.t("translation.deepRead")
        case (.grammar, _): return l10n.t("tool.grammar")
        }
    }

    // MARK: Errors

    private func errorView(_ message: String, retry: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.wrong)
                    .font(.system(size: 14))
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                if let retry {
                    Button(l10n.t("popup.retry"), action: retry)
                        .buttonStyle(CapsuleActionButtonStyle(emphasis: .primary))
                }
                Button(l10n.t("popup.configureService")) {
                    appState.openSettings()
                }
                .buttonStyle(CapsuleActionButtonStyle(emphasis: .secondary))
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.wrongSoft, lineWidth: 0.8)
        )
    }

    // MARK: Buttons

    private func actionRow(primary: (title: String, icon: String, action: () -> Void), showRetry: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                primary.action()
            } label: {
                Label(primary.title, systemImage: primary.icon)
            }
            .buttonStyle(CapsuleActionButtonStyle(emphasis: .primary))

            if showRetry {
                Button(l10n.t("popup.retry")) { appState.retry() }
                    .buttonStyle(CapsuleActionButtonStyle(emphasis: .secondary))
            }

            Button {
                appState.copyCorrectedText()
                showCopyFeedback()
            } label: {
                Label(showCopiedFeedback ? l10n.t("popup.copied") : l10n.t("popup.copy"), systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(CapsuleActionButtonStyle(emphasis: .secondary))

            Spacer()
        }
    }

    // MARK: Copy feedback

    private func showCopyFeedback() {
        let id = UUID()
        copyFeedbackID = id
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { showCopiedFeedback = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if copyFeedbackID == id {
                withAnimation(.easeInOut(duration: 0.2)) { showCopiedFeedback = false }
            }
        }
    }

    private func noticeBanner(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.fixed)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.fixedSoft)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
