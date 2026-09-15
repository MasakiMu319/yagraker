import SwiftUI

struct SettingsAboutPane: View {
    @EnvironmentObject private var l10n: L10n

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: ReIconAsset.yagrakerMark)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            Text("Yagraker")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(l10n.t("about.tagline"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSecondary)
            Text(l10n.t("about.version", appVersion, buildNumber))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
