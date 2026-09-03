import SwiftUI

/// Capsule label for themed dropdowns: fixed width, leading text, trailing
/// chevron. Replaces native popup-button chrome (white pill + accent arrow
/// chip) so Settings dropdowns align optically on the paper theme.
struct ThemedMenuLabel: View {
    let text: String
    var isPlaceholder = false
    var width: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isPlaceholder ? Theme.inkSecondary : Theme.ink)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .frame(width: width, height: 26, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.ink.opacity(0.05))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct ThemedMenuItemStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.ink.opacity(hovering || configuration.isPressed ? 0.07 : 0))
            )
            .onHover { hovering = $0 }
    }
}

/// Fixed-width dropdown rendered as a capsule button plus a popover list.
///
/// `Menu` with `.borderlessButton` cannot provide this look: on macOS 26 it
/// lifts the label's `Image` into a leading icon slot and ignores the label's
/// frame and background, which breaks capsule styling and optical alignment.
struct ThemedMenu<Option: Hashable>: View {
    /// Text shown on the capsule.
    let title: String
    /// Renders the capsule text in the secondary color (empty selection).
    var isPlaceholder = false
    let options: [Option]
    let label: (Option) -> String
    var isSelected: (Option) -> Bool = { _ in false }
    var header: String? = nil
    var emptyMessage: String? = nil
    var width: CGFloat = 220
    var accessibilityLabel: String = ""
    let onSelect: (Option) -> Void

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            ThemedMenuLabel(text: title, isPlaceholder: isPlaceholder, width: width)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            menuContent
                .frame(width: width)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            if options.isEmpty {
                Text(emptyMessage ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(options, id: \.self) { option in
                            Button {
                                onSelect(option)
                                isOpen = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                        .opacity(isSelected(option) ? 1 : 0)
                                    Text(label(option))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(ThemedMenuItemStyle())
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
