import Foundation
import MarkdownParser
import MarkdownView
import SwiftUI

/// Publishes replayable full snapshots of streamed Markdown text.
final class MarkdownStreamSource {
    let id = UUID()
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<String>.Continuation] = [:]
    private var snapshot = ""
    private var isFinished = false

    var text: AsyncStream<String> {
        let subscriberID = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(subscriberID)
            }

            lock.lock()
            let alreadyFinished = isFinished
            if !snapshot.isEmpty {
                continuation.yield(snapshot)
            }
            if !alreadyFinished {
                continuations[subscriberID] = continuation
            }
            lock.unlock()

            if alreadyFinished {
                continuation.finish()
            }
        }
    }

    func update(with snapshot: String) {
        let normalized = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        self.snapshot = normalized
        let activeContinuations = Array(continuations.values)
        lock.unlock()
        activeContinuations.forEach { $0.yield(normalized) }
    }

    func finish() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let activeContinuations = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        activeContinuations.forEach { $0.finish() }
    }

    private func removeContinuation(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}

/// AppKit-backed streaming renderer. Lakr233 MarkdownView deliberately avoids
/// SwiftUI paragraph intrinsic-size negotiation during every token update, which
/// prevents the rendered layer from drifting away from the view on macOS 27.
struct StreamingMarkdownView: View {
    let source: MarkdownStreamSource
    var theme: MarkdownTheme = TranslationMarkdownTheme.theme

    var body: some View {
        AppKitStreamingMarkdownView(source: source, theme: theme)
            .id(source.id)
    }
}

enum TranslationMarkdownTheme {
    @MainActor static var theme: MarkdownTheme {
        var theme = MarkdownTheme.default
        let body = NSFont.systemFont(ofSize: 13.5)
        theme.fonts.body = body
        theme.fonts.bold = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
        theme.fonts.italic = NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
        theme.fonts.code = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        theme.fonts.codeInline = theme.fonts.code
        theme.colors.body = NSColor(Theme.ink)
        theme.colors.emphasis = NSColor(Theme.accent)
        theme.colors.highlight = NSColor(Theme.accent)
        theme.colors.code = NSColor(Theme.ink)
        theme.colors.codeBackground = NSColor(Theme.cardSubtle)
        theme.colors.selectionBackground = NSColor(Theme.accentSoft)
        theme.spacings.paragraph = 12
        return theme
    }
}

private struct AppKitStreamingMarkdownView: NSViewRepresentable {
    let source: MarkdownStreamSource
    let theme: MarkdownTheme

    func makeCoordinator() -> Coordinator {
        Coordinator(source: source, theme: theme)
    }

    func makeNSView(context: Context) -> MarkdownTextView {
        let view = MarkdownTextView()
        view.theme = theme
        // Keep the horizontal layout under SwiftUI's control; vertical height is
        // measured below from the AppKit label and returned through sizeThatFits.
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: MarkdownTextView, context: Context) {
        context.coordinator.update(source: source, theme: theme, view: view)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView view: MarkdownTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        return context.coordinator.size(for: width, in: view)
    }

    static func dismantleNSView(_ view: MarkdownTextView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private var source: MarkdownStreamSource
        private var theme: MarkdownTheme
        private weak var view: MarkdownTextView?
        private var lastQueueTime = Date.distantPast
        private var task: Task<Void, Never>?
        private var lastSnapshot = ""
        private var lastAppliedSnapshot = ""
        private var lastAppliedTheme: MarkdownTheme?
        private var lastMeasuredWidth: CGFloat = -1
        private var lastMeasuredSize = CGSize.zero

        init(source: MarkdownStreamSource, theme: MarkdownTheme) {
            self.source = source
            self.theme = theme
        }

        func attach(to view: MarkdownTextView) {
            self.view = view
            apply("", force: true)
            start()
        }

        func update(source: MarkdownStreamSource, theme: MarkdownTheme, view: MarkdownTextView) {
            if self.source.id != source.id {
                detach()
                self.source = source
                self.view = view
                lastSnapshot = ""
                lastAppliedSnapshot = ""
                lastMeasuredWidth = -1
                apply("", force: true)
                start()
            }
            if self.theme != theme {
                self.theme = theme
                view.theme = theme
                lastAppliedTheme = theme
                lastMeasuredWidth = -1
            }
        }

        func size(for width: CGFloat, in view: MarkdownTextView) -> CGSize {
            if width == lastMeasuredWidth {
                return lastMeasuredSize
            }
            let size = view.boundingSize(for: width)
            lastMeasuredWidth = width
            lastMeasuredSize = size
            return size
        }

        func detach() {
            task?.cancel()
            task = nil
        }

        private func start() {
            let stream = source.text
            task = Task { [weak self] in
                for await snapshot in stream {
                    self?.receive(snapshot)
                }
            }
        }

        private func receive(_ snapshot: String) {
            guard snapshot != lastSnapshot else { return }
            lastSnapshot = snapshot
            apply(snapshot)
        }

        private func apply(_ snapshot: String, force: Bool = false) {
            guard let view else { return }
            guard force || snapshot != lastAppliedSnapshot || lastAppliedTheme != theme else { return }
            lastAppliedSnapshot = snapshot
            lastAppliedTheme = theme
            let now = Date()
            if force || now.timeIntervalSince(lastQueueTime) >= 1.0 / 20.0 {
                lastQueueTime = now
                view.setContentImmediately(
                    MarkdownContent(markdown: snapshot, theme: theme),
                    theme: theme
                )
            } else {
                // Let MarkdownView coalesce high-frequency token updates. Its own
                // 20fps throttle keeps the main thread responsive during streams.
                view.setContent(MarkdownContent(markdown: snapshot, theme: theme))
            }
            // Content updates are already coalesced and laid out by MarkdownView.
            // Do not force an extra intrinsic-size/layout round for every token.
            lastMeasuredWidth = -1
        }
}
}
