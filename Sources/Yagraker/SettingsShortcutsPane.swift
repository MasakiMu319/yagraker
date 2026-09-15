import SwiftUI
import KeyboardShortcuts

struct SettingsShortcutsPane: View {
    @EnvironmentObject private var l10n: L10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(l10n.t("settings.shortcuts.hint"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                shortcutRow(
                    title: l10n.t("shortcut.checkGrammar.title"),
                    detail: l10n.t("shortcut.checkGrammar.detail"),
                    name: .checkGrammar
                )
                shortcutRow(
                    title: l10n.t("shortcut.translate.title"),
                    detail: l10n.t("shortcut.translate.detail"),
                    name: .translate
                )
                shortcutRow(
                    title: l10n.t("shortcut.openTranslation.title"),
                    detail: l10n.t("shortcut.openTranslation.detail"),
                    name: .openTranslation
                )
                shortcutRow(
                    title: l10n.t("shortcut.openDeepRead.title"),
                    detail: l10n.t("shortcut.openDeepRead.detail"),
                    name: .openDeepRead
                )

                HStack {
                    Spacer()
                    Button(l10n.t("settings.shortcuts.reset")) {
                        KeyboardShortcuts.reset(
                            .checkGrammar, .translate, .openTranslation, .openDeepRead
                        )
                    }
                }
            }
            .padding(24)
        }
    }

    private func shortcutRow(title: String, detail: String, name: KeyboardShortcuts.Name) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            ShortcutRecorder(name: name)
                .frame(width: 150, height: 24)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.ink.opacity(0.035))
        )
    }
}
