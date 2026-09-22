import SwiftUI

/// The popup panel content: mode/provider header, input area, result area,
/// and action buttons.
struct PopupView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var toolPanel: ToolPanelModel
    @ObservedObject private var grammar: GrammarCoordinator
    @EnvironmentObject private var l10n: L10n
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showCopiedFeedback = false
    @State private var copyFeedbackID = UUID()

    init(grammar: GrammarCoordinator) {
        _grammar = ObservedObject(wrappedValue: grammar)
    }


    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PopupInputSectionView(
                        toolPanel: toolPanel,
                        grammar: grammar,
                        panelHeight: appState.panelHeight
                    )
                    if hasResultArea {
                        if toolPanel.mode == .grammar, !grammar.isLoading {
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

            if let notice = grammar.replacedNotice {
                noticeBanner(notice)
            }

            WindowResizeHandle()
        }
        .liquidGlassPanel()
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

    // MARK: Results

    private var hasResultArea: Bool {
        (toolPanel.mode == .grammar && grammar.isLoading)
            || grammar.errorMessage != nil
            || (toolPanel.mode == .grammar && grammar.correctionResult != nil)
            || (toolPanel.outputMode == toolPanel.mode && toolPanel.generationPhase != .idle)
    }

    @ViewBuilder
    private var resultArea: some View {
        if let error = grammar.errorMessage {
            PopupErrorView(
                message: error,
                retry: toolPanel.mode == .grammar ? { appState.retry() } : nil,
                onConfigure: { appState.openSettings() }
            )
        } else if toolPanel.mode == .grammar, grammar.isLoading {
            TextScanLoadingView(text: grammar.originalText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else if let result = grammar.correctionResult, toolPanel.mode == .grammar {
            PopupGrammarResultView(
                result: result,
                originalText: grammar.originalText,
                showCopiedFeedback: showCopiedFeedback,
                onAccept: { appState.replaceOriginalText() },
                onRetry: { appState.retry() },
                onCopy: {
                    appState.copyCorrectedText()
                    showCopyFeedback()
                }
            )
        } else if toolPanel.outputMode == toolPanel.mode,
                  (toolPanel.mode == .translation || toolPanel.mode == .deepRead) {
            PopupGenerationResultView(
                toolPanel: toolPanel,
                showCopiedFeedback: showCopiedFeedback,
                onCopy: {
                    toolPanel.copyOutput()
                    showCopyFeedback()
                },
                onConfigure: { appState.openSettings() }
            )
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
