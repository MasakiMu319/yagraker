import SwiftUI
import YagrakerCore

/// Editable credentials and endpoint configuration for one selected provider.
struct SettingsProviderCredentialsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isAPIKeyVisible: Bool
    let providerName: (LLMProviderKind) -> String
    let refreshModels: (LLMProviderKind) -> Void

    @EnvironmentObject private var l10n: L10n

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ProviderIcon(provider: viewModel.credentialProvider, size: 16)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.accentSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("settings.provider.editProvider"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(l10n.t("settings.provider.credentialsHint"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 10)
                ThemedMenu(
                    title: providerName(viewModel.credentialProvider),
                    options: LLMProviderKind.allCases,
                    label: { providerName($0) },
                    isSelected: { $0 == viewModel.credentialProvider },
                    width: 176,
                    accessibilityLabel: l10n.t("settings.provider.editProvider"),
                    onSelect: {
                        viewModel.credentialProvider = $0
                        isAPIKeyVisible = false
                    }
                )
            }
            .padding(12)
            divider

            if viewModel.credentialProvider == .custom {
                providerField(l10n.t("settings.provider.baseURL")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(
                            "https://api.example.com/v1",
                            text: draftBinding(viewModel.credentialProvider, keyPath: \.customBaseURL)
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(l10n.t("settings.provider.baseURL"))
                        Text(l10n.t("settings.provider.baseURLHelp"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                divider
            }

            if viewModel.credentialProvider == .qwen {
                providerField(l10n.t("settings.provider.baseURL")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(
                            QwenService.defaultBaseURL,
                            text: draftBinding(viewModel.credentialProvider, keyPath: \.qwenBaseURL)
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(l10n.t("settings.provider.baseURL"))
                        Text(l10n.t("settings.provider.qwenBaseURLHelp"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                divider
            }

            if viewModel.credentialProvider == .mimo {
                providerField(l10n.t("settings.provider.cluster")) {
                    let cluster = draftBinding(viewModel.credentialProvider, keyPath: \.mimoCluster)
                    ThemedMenu(
                        title: clusterName(cluster.wrappedValue),
                        options: MiMoCluster.allCases,
                        label: { clusterName($0) },
                        isSelected: { $0 == cluster.wrappedValue },
                        width: 220,
                        accessibilityLabel: l10n.t("settings.provider.cluster"),
                        onSelect: { cluster.wrappedValue = $0 }
                    )
                }
                divider
            }

            providerField(l10n.t("settings.provider.apiKey")) {
                HStack(spacing: 6) {
                    Group {
                        if isAPIKeyVisible {
                            TextField(
                                "••••••••••••••••",
                                text: draftBinding(viewModel.credentialProvider, keyPath: \.apiKey)
                            )
                        } else {
                            SecureField(
                                "••••••••••••••••",
                                text: draftBinding(viewModel.credentialProvider, keyPath: \.apiKey)
                            )
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(l10n.t("settings.provider.apiKey"))
                    .onSubmit {
                        refreshModels(viewModel.credentialProvider)
                    }

                    Button {
                        isAPIKeyVisible.toggle()
                    } label: {
                        Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityLabel(l10n.t(isAPIKeyVisible ? "settings.provider.hideAPIKey" : "settings.provider.showAPIKey"))
                    .accessibilityValue(l10n.t(isAPIKeyVisible ? "settings.provider.visible" : "settings.provider.hidden"))
                }
            }
            divider

            providerField(l10n.t("settings.provider.endpoint")) {
                Text(endpointLabel(for: viewModel.credentialProvider))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Theme.ink.opacity(0.04))
                    )
                    .help(endpointLabel(for: viewModel.credentialProvider))
            }
            divider

            providerHelp(for: viewModel.credentialProvider)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.ink.opacity(0.035))
        )
    }

    private func providerField<Content: View>(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 176, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func providerHelp(for provider: LLMProviderKind) -> some View {
        let (label, url) = providerHelpLink(for: provider)
        if let url {
            Link(destination: url) {
                Label(label, systemImage: "arrow.up.right.square")
                    .font(.system(size: 12))
            }
        } else {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func draftBinding<Value>(
        _ provider: LLMProviderKind,
        keyPath: WritableKeyPath<ProviderDraft, Value>
    ) -> Binding<Value> {
        Binding(
            get: { viewModel.providerDrafts[provider]![keyPath: keyPath] },
            set: { value in
                guard var draft = viewModel.providerDrafts[provider] else { return }
                draft[keyPath: keyPath] = value
                viewModel.providerDrafts[provider] = draft
            }
        )
    }

    private func clusterName(_ cluster: MiMoCluster) -> String {
        switch cluster {
        case .cn: return l10n.t("cluster.cn")
        case .sg: return l10n.t("cluster.sg")
        case .eu: return l10n.t("cluster.eu")
        }
    }

    private func endpointLabel(for provider: LLMProviderKind) -> String {
        let draft = viewModel.providerDrafts[provider]!
        switch provider {
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        case .qwen:
            let base = draft.qwenBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return (base.isEmpty ? QwenService.defaultBaseURL : base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) + "/chat/completions"
        case .deepseek:
            return "https://api.deepseek.com/chat/completions"
        case .mimo:
            return draft.mimoCluster.baseURL + "/chat/completions"
        case .custom:
            let base = draft.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return (base.isEmpty ? "{base}" : base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) + "/chat/completions"
        }
    }

    private func providerHelpLink(for provider: LLMProviderKind) -> (String, URL?) {
        switch provider {
        case .gemini:
            return (l10n.t("provider.help.gemini"), URL(string: "https://aistudio.google.com/apikey"))
        case .qwen:
            return (l10n.t("provider.help.qwen"), URL(string: "https://bailian.console.aliyun.com/"))
        case .deepseek:
            return (l10n.t("provider.help.deepseek"), URL(string: "https://platform.deepseek.com/api_keys"))
        case .mimo:
            return (l10n.t("provider.help.mimo"), URL(string: "https://platform.xiaomimimo.com"))
        case .custom:
            return (l10n.t("provider.help.custom"), nil)
        }
    }
}
