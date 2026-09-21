import SwiftUI
import YagrakerCore

/// Provider routing, credentials, model catalogs, and validation actions.
struct SettingsProviderPane: View {
    @EnvironmentObject var l10n: L10n
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isAPIKeyVisible: Bool
    let refreshConfiguration: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(l10n.t("settings.provider.hint"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    settingsSection(l10n.t("settings.provider.routing")) {
                        VStack(spacing: 0) {
                            taskRoutingRow(task: .translation, provider: routeBinding(for: .translation))
                            providerDivider
                            taskRoutingRow(task: .deepRead, provider: routeBinding(for: .deepRead))
                            providerDivider
                            taskRoutingRow(task: .grammar, provider: routeBinding(for: .grammar))
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Theme.ink.opacity(0.035))
                        )
                    }

                    settingsSection(l10n.t("settings.provider.credentials")) {
                        providerCredentialsCard
                    }
                }
                .padding(24)
            }

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)

            providerActions
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Theme.paper)
        }
        .onAppear {
            for provider in Set(viewModel.routeProviders.values) {
                ensureModelsLoaded(for: provider)
            }
        }
        .onChange(of: viewModel.routeProviders) { oldRoutes, newRoutes in
            for task in LLMTask.allCases {
                guard oldRoutes[task] != newRoutes[task], let provider = newRoutes[task] else { continue }
                ensureModelsLoaded(for: provider)
            }
        }
        .onChange(of: viewModel.providerDrafts) { oldDrafts, newDrafts in
            for provider in LLMProviderKind.allCases {
                guard catalogInput(for: provider, drafts: oldDrafts)
                    != catalogInput(for: provider, drafts: newDrafts) else { continue }
                invalidateModelCatalog(for: provider)
            }
        }
    }

    private func taskRoutingRow(
        task: LLMTask,
        provider: Binding<LLMProviderKind>
    ) -> some View {
        let selected = provider.wrappedValue
        return HStack(alignment: .center, spacing: 12) {
            ProviderIcon(provider: selected, size: 20)
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.accentSoft))

            VStack(alignment: .leading, spacing: 3) {
                Text(taskName(task))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(taskRouteHint(task))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 148, alignment: .leading)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                ThemedMenu(
                    title: providerName(provider.wrappedValue),
                    options: LLMProviderKind.allCases,
                    label: { providerName($0) },
                    isSelected: { $0 == provider.wrappedValue },
                    width: 260,
                    accessibilityLabel: l10n.t("settings.provider.provider"),
                    onSelect: { provider.wrappedValue = $0 }
                )

                modelPicker(for: task, provider: selected)
            }
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    private var providerCredentialsCard: some View {
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
            providerDivider

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
                providerDivider
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
                providerDivider
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
                providerDivider
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
                        refreshModels(for: viewModel.credentialProvider)
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
            providerDivider

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
            providerDivider

            providerHelp(for: viewModel.credentialProvider)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.ink.opacity(0.035))
        )
    }

    @ViewBuilder
    private func modelPicker(for task: LLMTask, provider: LLMProviderKind) -> some View {
        let currentModel = draftModel(for: provider, task: task)
        let options = modelOptions(for: provider, task: task)
        HStack(spacing: 5) {
            ThemedMenu(
                title: currentModel.isEmpty ? modelPlaceholder(for: provider, task: task) : currentModel,
                isPlaceholder: currentModel.isEmpty,
                options: options,
                label: { $0.label },
                isSelected: { $0.id == currentModel },
                header: l10n.t("settings.provider.officialModels"),
                emptyMessage: modelCatalogMessage(for: provider, task: task),
                width: 233,
                accessibilityLabel: modelAccessibilityLabel(task),
                onSelect: { setModel($0.id, for: provider, task: task) }
            )

            Button {
                refreshModels(for: provider)
            } label: {
                if case .loading = viewModel.modelCatalogs[provider] {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(.borderless)
            .frame(width: 22, height: 22)
            .help(l10n.t("settings.provider.refreshModels"))
            .accessibilityLabel(l10n.t("settings.provider.refreshModels"))
            .disabled({
                if case .loading = viewModel.modelCatalogs[provider] { return true }
                return false
            }())
        }
        .frame(width: 260)

        if let status = modelCatalogStatus(for: provider, task: task) {
            Text(status)
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(width: 260, alignment: .trailing)
        }

        if provider == .custom {
            TextField(
                modelPlaceholder(for: provider, task: task),
                text: modelBinding(for: provider, task: task)
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11.5))
            .accessibilityLabel(modelAccessibilityLabel(task))
            .frame(width: 260)
        }
    }

}
