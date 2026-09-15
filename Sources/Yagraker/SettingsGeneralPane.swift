import AppKit
import SwiftUI
import YagrakerCore

struct SettingsGeneralPane: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var l10n: L10n
    let accessibilityGranted: Bool
    let onRequestAccessibility: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsSection(l10n.t("settings.general.language")) {
                    settingsCard {
                        ThemedMenu(
                            title: languageName(l10n.language),
                            options: AppLanguage.allCases,
                            label: { languageName($0) },
                            isSelected: { $0 == l10n.language },
                            width: 220,
                            accessibilityLabel: l10n.t("settings.general.language"),
                            onSelect: { l10n.language = $0 }
                        )
                    }
                }

                settingsSection(l10n.t("settings.general.permissions")) {
                    settingsCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: accessibilityGranted ? "checkmark.shield.fill" : "lock.trianglebadge.exclamationmark.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(accessibilityGranted ? Theme.fixed : Theme.accent)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(accessibilityGranted ? Theme.fixedSoft : Theme.accentSoft))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(accessibilityGranted ? l10n.t("settings.permissions.granted") : l10n.t("settings.permissions.required"))
                                    .font(.system(size: 13, weight: .semibold))
                                if !accessibilityGranted {
                                    Text(l10n.t("settings.permissions.help"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.inkSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Button(l10n.t("settings.permissions.grant"), action: onRequestAccessibility)
                                }
                            }
                            Spacer()
                        }
                    }
                }

                settingsSection(l10n.t("settings.general.updates")) {
                    settingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(
                                l10n.t("settings.general.autoCheck"),
                                isOn: Binding(
                                    get: { appState.updater.automaticallyChecksForUpdates },
                                    set: { appState.updater.automaticallyChecksForUpdates = $0 }
                                )
                            )
                            .tint(Theme.accent)
                            Text(appState.updater.statusMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkSecondary)
                            if let date = appState.updater.lastCheckedAt {
                                Text(l10n.t("updater.status.lastChecked", Self.dateFormatter.string(from: date)))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            Button(l10n.t("settings.general.checkNow")) {
                                appState.updater.checkForUpdates()
                            }
                            .disabled(!appState.updater.canCheckForUpdates || appState.updater.isChecking)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func languageName(_ language: AppLanguage) -> String {
        switch language {
        case .system: return l10n.t("settings.language.system")
        case .english: return l10n.t("settings.language.english")
        case .simplifiedChinese: return l10n.t("settings.language.simplifiedChinese")
        case .traditionalChinese: return l10n.t("settings.language.traditionalChinese")
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
