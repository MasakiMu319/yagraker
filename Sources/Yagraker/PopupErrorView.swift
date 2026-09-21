import SwiftUI

struct PopupErrorView: View {
    let message: String
    let retry: (() -> Void)?
    let onConfigure: () -> Void

    @EnvironmentObject private var l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.wrong)
                    .font(.system(size: 14))
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                if let retry {
                    Button(l10n.t("popup.retry"), action: retry)
                        .buttonStyle(CapsuleActionButtonStyle(emphasis: .primary))
                }
                Button(l10n.t("popup.configureService"), action: onConfigure)
                    .buttonStyle(CapsuleActionButtonStyle(emphasis: .secondary))
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.wrongSoft, lineWidth: 0.8)
        )
    }
}
