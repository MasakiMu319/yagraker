import AppKit
import SwiftUI

/// Plain-text input editor (NSTextView wrapper):
/// - Enter submits, Shift+Enter inserts a newline
/// - Paste auto-submits (pasted text is usually a complete sentence);
///   lightweight Markdown decoration (**bold**, ## headings) is stripped on paste
struct QuickTranslationTextEditor: NSViewRepresentable {

    @Binding var text: String
    var placeholder: String
    /// Height bounds enforced inside the scroll view's intrinsic size —
    /// SwiftUI's `.frame(maxHeight:)` cannot clamp a self-sizing representable.
    var minHeight: CGFloat = 0
    var maxHeight: CGFloat = .greatestFiniteMagnitude
    var onSubmit: () -> Void
    var onPasteAndSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ContentSizedScrollView()
        scrollView.minimumContentHeight = minHeight
        scrollView.maximumContentHeight = maxHeight
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder

        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = NSColor(Theme.ink)
        textView.insertionPointColor = NSColor(Theme.ink)
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.string = text
        textView.onPasteAndSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onPasteAndSubmit()
        }
        textView.placeholderString = placeholder
        textView.setAccessibilityLabel(placeholder)
        EditorRegistry.shared.textView = textView

        scrollView.documentView = textView
        synchronizeDocumentWidth(textView, in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PasteAwareTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            textView.string = text
        }
        if textView.placeholderString != placeholder {
            textView.placeholderString = placeholder
            textView.setAccessibilityLabel(placeholder)
        }
        if let contentSized = scrollView as? ContentSizedScrollView,
           contentSized.minimumContentHeight != minHeight || contentSized.maximumContentHeight != maxHeight {
            contentSized.minimumContentHeight = minHeight
            contentSized.maximumContentHeight = maxHeight
        }
        synchronizeDocumentWidth(textView, in: scrollView)
        scrollView.invalidateIntrinsicContentSize()
        textView.needsDisplay = true
        scrollView.needsDisplay = true
    }

    private func synchronizeDocumentWidth(_ textView: NSTextView, in scrollView: NSScrollView) {
        let width = scrollView.contentSize.width
        guard width > 0, textView.frame.width != width else { return }
        textView.setFrameSize(
            NSSize(width: width, height: max(textView.frame.height, scrollView.contentSize.height))
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickTranslationTextEditor

        init(_ parent: QuickTranslationTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            textView.enclosingScrollView?.invalidateIntrinsicContentSize()
        }

        /// Enter → submit; Shift+Enter → newline.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               NSEvent.modifierFlags.contains(.shift) == false {
                parent.onSubmit()
                return true
            }
            return false
        }

        func textViewDidPaste() {
            // handled via onPasteAndSubmit closure
        }
    }

    /// NSTextView that strips trivial Markdown markers on paste and auto-submits.
    final class PasteAwareTextView: NSTextView {
        var onPasteAndSubmit: (() -> Void)?
        var placeholderString: String = "" {
            didSet { needsDisplay = true }
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if string.isEmpty && !placeholderString.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor(Theme.inkSecondary),
                ]
                // Align exactly with the real text origin (container inset +
                // line-fragment padding) so the placeholder sits where typed
                // text would — and the caret hugs its leading edge instead of
                // overlapping the first glyph.
                let origin = NSPoint(
                    x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                    y: textContainerInset.height
                )
                placeholderString.draw(at: origin, withAttributes: attributes)
            }
        }

        override func paste(_ sender: Any?) {
            super.paste(sender)
            stripMarkdownDecorations()
            onPasteAndSubmit?()
        }

        override func pasteAsPlainText(_ sender: Any?) {
            super.pasteAsPlainText(sender)
            stripMarkdownDecorations()
            onPasteAndSubmit?()
        }

        /// Removes pasted bold markers and heading prefixes before submission.
        private func stripMarkdownDecorations() {
            var value = string
            if let bold = try? NSRegularExpression(pattern: #"\*\*([^\n]+?)\*\*"#) {
                value = bold.stringByReplacingMatches(
                    in: value,
                    range: NSRange(value.startIndex..., in: value),
                    withTemplate: "$1"
                )
            }
            if let headings = try? NSRegularExpression(pattern: #"(?m)^#{1,3}\s+(.+)$"#) {
                value = headings.stringByReplacingMatches(
                    in: value,
                    range: NSRange(value.startIndex..., in: value),
                    withTemplate: "$1"
                )
            }
            if value != string {
                string = value
            }
        }

        // MARK: Breathing caret

        private static let breathingPeriod: TimeInterval = 2.4
        private var caretPhase: TimeInterval = PasteAwareTextView.breathingPeriod / 4
        private var caretSolidUntil = Date.distantPast
        private var caretTimer: Timer?
        private var lastCaretRect = NSRect.zero

        /// Solid while typing; a slow sinusoidal fade when idle.
        private var caretAlpha: CGFloat {
            guard Date() >= caretSolidUntil else { return 1 }
            let wave = 0.5 + 0.5 * sin(2 * .pi * caretPhase / Self.breathingPeriod)
            return 0.45 + 0.55 * wave
        }

        override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
            lastCaretRect = rect
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
                return
            }
            color.withAlphaComponent(caretAlpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }

        override func updateInsertionPointStateAndRestartTimer(_ restartDelay: Bool) {
            super.updateInsertionPointStateAndRestartTimer(restartDelay)
            if restartDelay {
                caretSolidUntil = Date().addingTimeInterval(0.5)
                caretPhase = Self.breathingPeriod / 4
            }
            startCaretTimer()
        }

        override func becomeFirstResponder() -> Bool {
            let didBecome = super.becomeFirstResponder()
            if didBecome { startCaretTimer() }
            return didBecome
        }

        override func resignFirstResponder() -> Bool {
            let didResign = super.resignFirstResponder()
            if didResign { stopCaretTimer() }
            return didResign
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stopCaretTimer() }
        }

        private func startCaretTimer() {
            guard caretTimer == nil,
                  !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.caretPhase += 1.0 / 30.0
                guard Date() >= self.caretSolidUntil, !self.lastCaretRect.isEmpty else { return }
                self.setNeedsDisplay(self.lastCaretRect.insetBy(dx: -1, dy: -1))
            }
            RunLoop.main.add(timer, forMode: .common)
            caretTimer = timer
        }

        private func stopCaretTimer() {
            caretTimer?.invalidate()
            caretTimer = nil
        }

        deinit {
            caretTimer?.invalidate()
        }
    }
}

/// Scroll view that reports the laid-out height of its text document to
/// SwiftUI. Without an intrinsic height, an `NSViewRepresentable` scroll view
/// collapses to its frame's minimum, ignoring any `.frame(maxHeight:)` budget.
final class ContentSizedScrollView: NSScrollView {
    /// Height clamps applied to the intrinsic size; SwiftUI frame modifiers
    /// cannot reliably clamp a self-sizing NSViewRepresentable.
    var minimumContentHeight: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }
    var maximumContentHeight: CGFloat = .greatestFiniteMagnitude {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: NSSize {
        let height = min(max(contentHeight, minimumContentHeight), maximumContentHeight)
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }
    private var contentHeight: CGFloat {
        guard let textView = documentView as? NSTextView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return 0
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer).height
        return ceil(used + textView.textContainerInset.height * 2)
    }
}
