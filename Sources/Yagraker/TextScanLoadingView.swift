import NaturalLanguage
import SwiftUI

/// Highlights successive words while a request is in flight.
struct TextScanLoadingView: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct ScanWord: Identifiable, Hashable {
        let id: Int
        let text: String
    }

    private struct ScanLine: Identifiable, Hashable {
        let id: Int
        let words: [ScanWord]
    }

    private let lines: [ScanLine]
    private let totalWordCount: Int
    private let scanInterval: TimeInterval

    init(text: String) {
        self.text = text
        let rawLines = text.components(separatedBy: "\n")
        let tokenizer = NLTokenizer(unit: .word)
        var parsedLines: [ScanLine] = []
        var wordCounter = 0
        for (lineIdx, rawLine) in rawLines.enumerated() {
            let words = Self.scanWords(in: rawLine, startingAt: wordCounter, tokenizer: tokenizer)
            wordCounter += words.count
            parsedLines.append(ScanLine(id: lineIdx, words: words))
        }
        self.lines = parsedLines
        self.totalWordCount = wordCounter
        let wordCount = max(wordCounter, 1)
        self.scanInterval = min(0.80, max(0.14, 1.80 / Double(wordCount)))
    }

    private static func scanWords(in line: String, startingAt baseIndex: Int, tokenizer: NLTokenizer) -> [ScanWord] {
        guard !line.isEmpty else { return [ScanWord(id: baseIndex, text: " ")] }

        tokenizer.string = line
        var pieces: [String] = []
        var cursor = line.startIndex
        tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { range, _ in
            if cursor < range.lowerBound {
                pieces.append(String(line[cursor..<range.lowerBound]))
            }
            pieces.append(String(line[range]))
            cursor = range.upperBound
            return true
        }
        if cursor < line.endIndex {
            pieces.append(String(line[cursor..<line.endIndex]))
        }
        if pieces.isEmpty {
            pieces.append(line)
        }
        return pieces.enumerated().map { ScanWord(id: baseIndex + $0.offset, text: $0.element) }
    }

    private var scanAnimation: Animation {
        .easeInOut(duration: scanInterval)
    }

    @State private var scanIndex = 0

    private func highlightOpacity(wordId: Int) -> Double {
        guard !reduceMotion, totalWordCount > 0 else { return 0 }
        let current = scanIndex % totalWordCount
        let distanceBehind = (current - wordId + totalWordCount) % totalWordCount
        switch distanceBehind {
        case 0: return 0.44
        case 1: return 0.18
        case 2: return 0.07
        default: return 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines) { line in
                FlowLayout(spacing: 0, rowSpacing: 2) {
                    ForEach(line.words) { word in
                        Text(word.text.isEmpty ? " " : word.text)
                            .padding(.horizontal, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Theme.accent.opacity(highlightOpacity(wordId: word.id)))
                            )
                    }
                }
            }
        }
        .foregroundStyle(Theme.inkSecondary)
        .animation(scanAnimation, value: scanIndex)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(scanInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                scanIndex = (scanIndex + 1) % max(totalWordCount, 1)
            }
        }
    }
}
