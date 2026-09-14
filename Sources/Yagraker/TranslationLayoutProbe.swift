import AppKit
import OSLog
import SwiftUI

/// Temporary, opt-in diagnostics. Never records text, prompts, credentials or URLs.
/// Enable before launch with YAGRAKER_DEBUG_TRANSLATION_LAYOUT=1.
enum TranslationLayoutDiagnostics {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["YAGRAKER_DEBUG_TRANSLATION_LAYOUT"] == "1"
    }

    static let logger = Logger(subsystem: "Yagraker", category: "TranslationLayout")

}

struct TranslationLayoutProbe: NSViewRepresentable {
    let streamID: UUID
    let outputUTF16Count: Int
    let isStreaming: Bool

    func makeNSView(context: Context) -> ProbeView { ProbeView() }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.streamID = streamID.uuidString
        view.outputUTF16Count = outputUTF16Count
        view.isStreaming = isStreaming
    }

    static func dismantleNSView(_ view: ProbeView, coordinator: ()) {
        view.stop()
    }

    final class ProbeView: NSView {
        var streamID = ""
        var outputUTF16Count = 0
        var isStreaming = false
        private var timer: Timer?
        private var previousPayload: Data?
        private var sequence = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            // Read after layout rather than publishing geometry back into SwiftUI.
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.sample()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        deinit { timer?.invalidate() }

        private func sample() {
            guard let window, window.isVisible, let root = window.contentView else { return }
            var texts: [[String: Any]] = []
            var scrolls: [[String: Any]] = []
            var rendering: [[String: Any]] = []
            func visit(_ view: NSView) {
                if let text = view as? NSTextView, texts.count < 24 {
                    let isSource = text is QuickTranslationTextEditor.PasteAwareTextView
                    var item: [String: Any] = [
                        "id": String(describing: ObjectIdentifier(text)),
                        "role": isSource ? "source" : "rendered",
                        "utf16": text.string.utf16.count,
                        "windowRect": rect(text.convert(text.bounds, to: nil)),
                        "topFromWindowTop": window.frame.height - text.convert(text.bounds, to: nil).maxY,
                        "hidden": text.isHiddenOrHasHiddenAncestor,
                        "frame": rect(text.frame),
                        "bounds": rect(text.bounds),
                        "textOrigin": [text.textContainerOrigin.x, text.textContainerOrigin.y],
                        "inset": [text.textContainerInset.width, text.textContainerInset.height],
                        "flipped": text.isFlipped
                    ]
                    if let scroll = text.enclosingScrollView as? ContentSizedScrollView {
                        item["heightLimits"] = [scroll.minimumContentHeight, scroll.maximumContentHeight]
                    }
                    if let container = text.textContainer {
                        item["containerSize"] = [container.size.width, container.size.height]
                    }
                    texts.append(item)
                    if !isSource && rendering.isEmpty {
                        rendering = renderingMetrics(for: text, in: window)
                    }
                }
                if let scroll = view as? NSScrollView, scrolls.count < 24 {
                    scrolls.append([
                        "id": String(describing: ObjectIdentifier(scroll)),
                        "role": scroll is ContentSizedScrollView ? "source" : "outerOrRenderer",
                        "windowRect": rect(scroll.convert(scroll.bounds, to: nil)),
                        "clipBounds": rect(scroll.contentView.bounds),
                        "documentFrame": rect(scroll.documentView?.frame ?? .zero)
                    ])
                }
                for child in view.subviews { visit(child) }
            }
            visit(root)
            let resultRect = convert(bounds, to: nil)
            let payload: [String: Any] = [
                "stream": streamID,
                "streaming": isStreaming,
                "rendering": rendering,
                "outputUTF16": outputUTF16Count,
                "panelFrame": rect(window.frame),
                "resultWindowRect": rect(resultRect),
                "resultTopFromWindowTop": window.frame.height - resultRect.maxY,
                "texts": texts,
                "scrolls": scrolls
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                  data != previousPayload else { return }
            previousPayload = data
            sequence += 1
            // Unified logging truncates long messages. Keep each view in its own
            // record; stream + sequence correlate one atomic sample.
            var summary = payload
            summary.removeValue(forKey: "texts")
            summary.removeValue(forKey: "scrolls")
            summary.removeValue(forKey: "rendering")
            emit(kind: "summary", fields: summary)
            for text in texts { emit(kind: "text", fields: text) }
            for scroll in scrolls { emit(kind: "scroll", fields: scroll) }
            for record in rendering { emit(kind: "rendering", fields: record) }
        }

        private func renderingMetrics(for text: NSTextView, in window: NSWindow) -> [[String: Any]] {
            var records: [[String: Any]] = []
            // Only inspect the already laid-out prefix. Never call ensureLayout,
            // firstRect(forCharacterRange:) or sizeToFit: those can mask this bug.
            if let manager = text.layoutManager, manager.firstUnlaidCharacterIndex() > 0 {
                let glyph = manager.glyphIndexForCharacter(at: 0)
                let line = manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil,
                                                       withoutAdditionalLayout: true)
                let local = line.offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
                let inWindow = text.convert(local, to: nil)
                records.append([
                    "type": "firstLine", "textID": String(describing: ObjectIdentifier(text)),
                    "laidOutCharacters": manager.firstUnlaidCharacterIndex(),
                    "lineLocal": rect(local), "lineWindow": rect(inWindow),
                    "lineTopFromWindowTop": window.frame.height - inWindow.maxY
                ])
            }
            // Presentation geometry includes in-flight CA animations that NSView
            // frame/convert do not expose. Include ancestors: SwiftUI can animate
            // a wrapper while the text layer itself has no animation keys.
            var current = text.layer
            var depth = 0
            while let layer = current, depth < 10 {
                var record: [String: Any] = [
                    "type": "layer", "depth": depth,
                    "modelFrame": rect(layer.frame), "modelBounds": rect(layer.bounds),
                    "anchor": [layer.anchorPoint.x, layer.anchorPoint.y],
                    "flipped": layer.isGeometryFlipped,
                    "animationCount": layer.animationKeys()?.count ?? 0
                ]
                if let presentation = layer.presentation() {
                    record["presentationFrame"] = rect(presentation.frame)
                    record["presentationBounds"] = rect(presentation.bounds)
                    record["positionDelta"] = [presentation.position.x - layer.position.x,
                                               presentation.position.y - layer.position.y]
                    record["frameDelta"] = [presentation.frame.minX - layer.frame.minX,
                                            presentation.frame.minY - layer.frame.minY]
                } else {
                    record["frameDelta"] = [0, 0]
                }
                records.append(record)
                current = layer.superlayer
                depth += 1
            }
            return records
        }

        private func emit(kind: String, fields: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else { return }
            TranslationLayoutDiagnostics.logger.info("[DEBUG-translate-layout] stream=\(self.streamID, privacy: .public) seq=\(self.sequence) kind=\(kind, privacy: .public) \(json, privacy: .public)")
        }

        private func rect(_ rect: NSRect) -> [CGFloat] {
            [rect.origin.x, rect.origin.y, rect.width, rect.height]
        }
    }
}
