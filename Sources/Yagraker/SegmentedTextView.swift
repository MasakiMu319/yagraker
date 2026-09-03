import SwiftUI
import YagrakerCore

/// Renders corrections inline in the original text. Unlike a FlowLayout of
/// chips, Text concatenation preserves natural word wrapping for long input.
struct SegmentedTextView: View {
    let originalText: String
    let corrections: [Correction]

    private var segments: [TextSegment] {
        TextSegment.segments(for: originalText, corrections: corrections)
    }

    var body: some View {
        segments.reduce(Text("")) { partial, segment in
            partial + text(for: segment)
        }
        .font(.system(size: 13))
        .lineSpacing(3)
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func text(for segment: TextSegment) -> Text {
        switch segment {
        case .plain(let text):
            return Text(text)
        case .correction(let correction):
            return inlineDiffText(for: correction)
        }
    }

    private func inlineDiffText(for correction: Correction) -> Text {
        let chunks = InlineDiff.diff(original: correction.original, corrected: correction.corrected)
        guard !chunks.isEmpty else {
            return Text(correction.corrected)
        }

        var result = Text("")
        for (index, chunk) in chunks.enumerated() {
            switch chunk {
            case .unchanged(let s):
                result = result + Text(s)
            case .deleted(let s):
                result = result + Text(s)
                    .strikethrough()
                    .foregroundStyle(Theme.wrong)
                if index + 1 < chunks.count, case .inserted(let nextS) = chunks[index + 1] {
                    if shouldAddSpacing(after: s, before: nextS) {
                        result = result + Text(" ")
                    }
                }
            case .inserted(let s):
                result = result + Text(s)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.fixed)
            }
        }
        return result
    }

    private func shouldAddSpacing(after deleted: String, before inserted: String) -> Bool {
        guard let last = deleted.last, let first = inserted.first else { return false }
        if last.isWhitespace || first.isWhitespace { return false }
        return (last.isLetter || last.isNumber) && (first.isLetter || first.isNumber)
    }
}
