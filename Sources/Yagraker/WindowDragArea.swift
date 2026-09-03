import AppKit
import SwiftUI

/// Explicit draggable empty region for the borderless floating panel.
struct WindowDragHandle: View {
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void

    init(
        onChanged: @escaping (CGSize) -> Void = { _ in },
        onEnded: @escaping () -> Void = {}
    ) {
        self.onChanged = onChanged
        self.onEnded = onEnded
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in onChanged(value.translation) }
                    .onEnded { _ in onEnded() }
            )
    }
}

struct WindowResizeHandle: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var l10n: L10n

    @State private var initialSize: NSSize?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                WindowResizeGrip()
                    .stroke(
                        Theme.inkSecondary.opacity(isHovering ? 0.62 : 0.32),
                        style: StrokeStyle(lineWidth: 1.25, lineCap: .round)
                    )
                    .frame(width: 14, height: 14)
                    .padding(.trailing, 5)
                    .padding(.bottom, 3)
            }
            .frame(width: 30, height: 20)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if initialSize == nil {
                            initialSize = appState.popupWindow.currentSize
                            appState.popupWindow.beginManualResize()
                        }
                        guard let initialSize else { return }
                        appState.popupWindow.resizeManually(
                            to: NSSize(
                                width: initialSize.width + value.translation.width,
                                height: initialSize.height + value.translation.height
                            )
                        )
                    }
                    .onEnded { _ in
                        appState.popupWindow.endManualResize()
                        initialSize = nil
                    }
            )
            .help(l10n.t("popup.resizeWindow"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(l10n.t("popup.resizeWindow"))
            .accessibilityAdjustableAction { direction in
                let delta: CGFloat
                switch direction {
                case .increment:
                    delta = 40
                case .decrement:
                    delta = -40
                @unknown default:
                    return
                }
                let currentSize = appState.popupWindow.currentSize
                appState.popupWindow.beginManualResize()
                appState.popupWindow.resizeManually(
                    to: NSSize(
                        width: currentSize.width + delta,
                        height: currentSize.height + delta
                    )
                )
                appState.popupWindow.endManualResize()
            }
        }
        .frame(height: 20)
    }
}

private struct WindowResizeGrip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner = CGPoint(x: rect.maxX - 1, y: rect.maxY - 1)
        for offset: CGFloat in [4, 8, 12] {
            path.move(to: CGPoint(x: corner.x - offset, y: corner.y))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y - offset))
        }
        return path
    }
}
