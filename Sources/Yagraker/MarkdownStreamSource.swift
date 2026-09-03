import Foundation
import SwiftStreamingMarkdown
import SwiftUI

/// Publishes replayable full snapshots of streamed Markdown text.
final class MarkdownStreamSource: StreamedMarkdownSource {
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

struct StreamingMarkdownView: View {
    let source: MarkdownStreamSource
    var config: MarkdownRenderConfig = .default

    var body: some View {
        StreamedMarkdownView(source: source, config: config)
            .id(source.id)
    }
}
