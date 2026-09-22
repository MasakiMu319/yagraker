import NaturalLanguage
import SwiftUI

/// Shows a quiet document-analysis state while a grammar request is in flight.
struct TextScanLoadingView: View {
    let text: String
    let statusTitle: String
    let statusDetail: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepPhase = false

    private struct ScanWord: Identifiable, Hashable {
        let id: Int
        let text: String
    }

    private struct ScanLine: Identifiable, Hashable {
        let id: Int
        let words: [ScanWord]
    }

    private let lines: [ScanLine]

    init(
        text: String,
        statusTitle: String = "Checking grammar",
        statusDetail: String = "Looking for grammar, spelling, and phrasing issues"
    ) {
        self.text = text
        self.statusTitle = statusTitle
        self.statusDetail = statusDetail

        let tokenizer = NLTokenizer(unit: .word)
        var parsedLines: [ScanLine] = []
        var wordCounter = 0
        for (lineIndex, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let words = Self.scanWords(in: rawLine, startingAt: wordCounter, tokenizer: tokenizer)
            wordCounter += words.count
            parsedLines.append(ScanLine(id: lineIndex, words: words))
        }
        lines = parsedLines
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader
            scanTrack
            textPreview
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.cardSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 0.7)
        )
        .onAppear(perform: startSweep)
        .onDisappear { sweepPhase = false }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusTitle)
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accentSoft)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(statusDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            LoadingDots()
        }
    }

    private var scanTrack: some View {
        GeometryReader { proxy in
            let segmentWidth = min(72, max(36, proxy.size.width * 0.24))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.hairline)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: segmentWidth, height: 3)
                    .offset(x: reduceMotion ? 0 : (sweepPhase ? proxy.size.width : -segmentWidth))
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(lines) { line in
                FlowLayout(spacing: 0, rowSpacing: 2) {
                    ForEach(line.words) { word in
                        Text(word.text.isEmpty ? " " : word.text)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startSweep() {
        guard !reduceMotion else { return }
        sweepPhase = false
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
            sweepPhase = true
        }
    }
}

private struct LoadingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeIndex = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 4, height: 4)
                    .scaleEffect(reduceMotion || activeIndex == index ? 1 : 0.72)
                    .opacity(reduceMotion || activeIndex == index ? 0.82 : 0.32)
            }
        }
        .frame(width: 22, height: 14)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 260_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    activeIndex = (activeIndex + 1) % 3
                }
            }
        }
    }
}
