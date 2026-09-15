import AppKit

/// Coordinates popup input/mode transitions and the corresponding panel relayout.
@MainActor
final class PopupCoordinator {
    struct Result {
        let needsSettle: Bool
    }

    func handleInputChanged(
        _ input: String,
        toolPanel: ToolPanelModel,
        grammar: GrammarCoordinator
    ) -> Result {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            var needsSettle = false
            if grammar.correctionResult != nil {
                grammar.correctionResult = nil
                grammar.originalText = ""
                needsSettle = true
            }
            if grammar.replacedNotice != nil {
                grammar.replacedNotice = nil
            }
            if toolPanel.hasOutput || toolPanel.generationPhase != .idle {
                toolPanel.cancelGeneration(clearOutput: true)
                needsSettle = true
            }
            return Result(needsSettle: needsSettle)
        }

        if toolPanel.mode == .grammar,
           grammar.correctionResult != nil,
           input != grammar.originalText {
            grammar.correctionResult = nil
            grammar.replacedNotice = nil
            return Result(needsSettle: true)
        }

        if (toolPanel.mode == .translation || toolPanel.mode == .deepRead),
           toolPanel.generationPhase == .done,
           input != toolPanel.lastGeneratedInput {
            toolPanel.cancelGeneration(clearOutput: true)
            return Result(needsSettle: true)
        }

        return Result(needsSettle: false)
    }

    func handleModeChanged(grammar: GrammarCoordinator) {
        grammar.errorMessage = nil
        grammar.replacedNotice = nil
    }
}
