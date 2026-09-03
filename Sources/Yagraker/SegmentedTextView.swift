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
            return Text(correction.original)
                .strikethrough()
                .foregroundStyle(Theme.wrong)
            + Text(" ")
            + Text(correction.corrected)
                .fontWeight(.medium)
                .foregroundStyle(Theme.fixed)
        }
    }
}
