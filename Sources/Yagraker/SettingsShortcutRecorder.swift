import AppKit
import KeyboardShortcuts
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let name: KeyboardShortcuts.Name

    func makeNSView(context: Context) -> RecorderView {
        RecorderView(name: name)
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        if view.recorder.shortcutName != name {
            view.recorder.shortcutName = name
        }
        view.updateAccessibilityLabel()
    }

    final class RecorderView: NSView {
        private final class ImmediateButton: NSButton {
            var onMouseDown: (() -> Void)?

            override func mouseDown(with event: NSEvent) {
                guard isEnabled else { return }
                onMouseDown?()
            }

            override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
                true
            }
        }

        let recorder: KeyboardShortcuts.RecorderCocoa
        private let recordButton = ImmediateButton()
        private let clearButton = ImmediateButton()

        init(name: KeyboardShortcuts.Name) {
            recorder = KeyboardShortcuts.RecorderCocoa(for: name)
            super.init(frame: recorder.frame)

            addSubview(recorder)

            configureButton(recordButton)
            recordButton.setAccessibilityLabel(L10n.shared.t("settings.shortcuts.record"))
            recordButton.onMouseDown = { [weak self] in self?.beginRecording() }
            addSubview(recordButton)

            configureButton(clearButton)
            clearButton.setAccessibilityLabel(L10n.shared.t("settings.shortcuts.clear"))
            clearButton.onMouseDown = { [weak self] in self?.clearShortcut() }
            addSubview(clearButton)
        }

        private func configureButton(_ button: NSButton) {
            button.isBordered = false
            button.isTransparent = true
            button.focusRingType = .none
            button.refusesFirstResponder = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            recorder.intrinsicContentSize
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func layout() {
            super.layout()
            recorder.frame = bounds
            let width = min(bounds.width, max(32, bounds.height))
            let clearFrame = NSRect(
                x: bounds.maxX - width,
                y: bounds.minY,
                width: width,
                height: bounds.height
            )
            clearButton.frame = clearFrame
            recordButton.frame = bounds
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            if !recorder.stringValue.isEmpty, clearButton.frame.contains(point) {
                return clearButton
            }
            return recordButton
        }

        func updateAccessibilityLabel() {
            recordButton.setAccessibilityLabel(L10n.shared.t("settings.shortcuts.record"))
            clearButton.setAccessibilityLabel(L10n.shared.t("settings.shortcuts.clear"))
        }

        private func beginRecording() {
            window?.makeFirstResponder(recorder)
        }

        private func clearShortcut() {
            KeyboardShortcuts.setShortcut(nil, for: recorder.shortcutName)
            recorder.abortEditing()
            window?.makeFirstResponder(nil)
        }
    }
}
