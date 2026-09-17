import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI
import YagrakerCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, provider, shortcuts, about
    var id: String { rawValue }

    var icon: Image {
        Image(nsImage: iconImage)
    }

    private var iconImage: NSImage {
        switch self {
        case .general: return ReIconAsset.settings
        case .provider: return ReIconAsset.sparkles
        case .shortcuts: return ReIconAsset.keyboard
        case .about: return ReIconAsset.infoCircle
        }
    }

    @MainActor
    func title(_ l10n: L10n) -> String {
        l10n.t("settings.tab.\(rawValue)")
    }
}

struct SettingsTabBar: View {
    private static let segmentWidth: CGFloat = 112
    private static let segmentHeight: CGFloat = 54
    private static let selectionWidth: CGFloat = 104
    private static let selectionHeight: CGFloat = 48

    @EnvironmentObject private var l10n: L10n
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTab: SettingsTab

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.accentSoft)
                .frame(width: Self.selectionWidth, height: Self.selectionHeight)
                .offset(x: selectionOffset)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    let selected = selectedTab == tab
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 3) {
                            tab.icon
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .accessibilityHidden(true)
                            Text(tab.title(l10n))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(selected ? Theme.accent : Theme.inkSecondary)
                        .frame(width: Self.segmentWidth, height: Self.segmentHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CapsuleSegmentButtonStyle(isSelected: selected))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .frame(
            width: Self.segmentWidth * CGFloat(SettingsTab.allCases.count),
            height: Self.segmentHeight
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: selectedTab)
    }

    private var selectionOffset: CGFloat {
        let index = SettingsTab.allCases.firstIndex(of: selectedTab)!
        return CGFloat(index) * Self.segmentWidth + (Self.segmentWidth - Self.selectionWidth) / 2
    }
}

/// Four-pane settings surface.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var l10n: L10n
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTab: SettingsTab = .general
    @State private var accessibilityGranted = SelectionReader.isAccessibilityGranted

    @StateObject private var viewModel = SettingsViewModel()
    @State private var isAPIKeyVisible = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selectedTab: $selectedTab)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Group {
                switch selectedTab {
                case .general: generalPane
                case .provider: providerPane
                case .shortcuts: shortcutsPane
                case .about: aboutPane
                }
            }
            .id(selectedTab)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selectedTab)
        }
        .frame(width: 620, height: 520)
        .background(Theme.paper)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = SelectionReader.isAccessibilityGranted
        }
    }

    private var generalPane: some View {
        SettingsGeneralPane(accessibilityGranted: accessibilityGranted) {
            accessibilityGranted = SelectionReader.promptForAccessibilityIfNeeded()
            if !accessibilityGranted,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: Provider

    private var providerPane: some View {
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

    private var providerDivider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    private var providerActions: some View {
        HStack(alignment: .center, spacing: 8) {
            if let validationMessage = viewModel.validationMessage {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: viewModel.validationSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(viewModel.validationSucceeded ? Theme.fixed : Theme.wrong)
                    Text(validationMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let saveMessage = viewModel.saveMessage {
                Label(saveMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.fixed)
            }

            Spacer(minLength: 12)

            ThemedMenu(
                title: taskName(viewModel.validationTask),
                options: LLMTask.allCases,
                label: { taskName($0) },
                isSelected: { $0 == viewModel.validationTask },
                width: 132,
                accessibilityLabel: l10n.t("settings.provider.validateTask"),
                onSelect: { viewModel.validationTask = $0 }
            )

            Button(l10n.t("settings.provider.save")) {
                persistProvider(showFeedback: true)
            }
            Button(viewModel.isValidating ? l10n.t("settings.provider.validating") : validateButtonTitle) {
                validateProvider()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(viewModel.isValidating)
            .keyboardShortcut(.defaultAction)
        }
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

    private var shortcutsPane: some View {
        SettingsShortcutsPane()
    }

    private var aboutPane: some View {
        SettingsAboutPane()
    }

    // MARK: Provider actions

    private func persistProvider(showFeedback: Bool) {
        viewModel.persistProvider(showFeedback: showFeedback, l10n: l10n) {
            appState.toolPanelModel.refreshConfiguration()
        }
    }

    private func validateProvider() {
        viewModel.validateProvider(l10n: l10n) {
            appState.toolPanelModel.refreshConfiguration()
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

    private func routeProvider(for task: LLMTask) -> LLMProviderKind {
        viewModel.routeProviders[task] ?? .gemini
    }

    private func routeBinding(for task: LLMTask) -> Binding<LLMProviderKind> {
        Binding(
            get: { routeProvider(for: task) },
            set: { viewModel.routeProviders[task] = $0 }
        )
    }

    private func draftModel(for provider: LLMProviderKind, task: LLMTask) -> String {
        viewModel.providerDrafts[provider]?.model(for: task)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func modelBinding(for provider: LLMProviderKind, task: LLMTask) -> Binding<String> {
        Binding(
            get: { viewModel.providerDrafts[provider]?.model(for: task) ?? "" },
            set: { model in
                guard var draft = viewModel.providerDrafts[provider] else { return }
                draft.setModel(model, for: task)
                viewModel.providerDrafts[provider] = draft
            }
        )
    }

    private func setModel(_ model: String, for provider: LLMProviderKind, task: LLMTask) {
        modelBinding(for: provider, task: task).wrappedValue = model
    }

    private func ensureModelsLoaded(for provider: LLMProviderKind) {
        viewModel.ensureModelsLoaded(for: provider, l10n: l10n)
    }

    private func refreshModels(for provider: LLMProviderKind) {
        viewModel.refreshModels(for: provider, l10n: l10n)
    }

    private func modelOptions(
        for provider: LLMProviderKind,
        task: LLMTask
    ) -> [LLMModel] {
        let catalog: [LLMModel]
        if case .loaded(let loaded) = viewModel.modelCatalogs[provider] {
            catalog = loaded
        } else {
            catalog = []
        }
        return catalog.filter { model in
            switch provider {
            case .qwen:
                // Qwen-MT models are translation-only, but translation itself
                // works with any model — general-purpose LLMs translate too.
                return task == .translation || !QwenService.isMachineTranslationModel(model.id)
            case .mimo:
                return MiMoService.isTextGenerationModel(model.id)
            case .gemini, .deepseek, .custom:
                return true
            }
        }
    }

    private func modelCatalogMessage(for provider: LLMProviderKind, task: LLMTask) -> String {
        switch viewModel.modelCatalogs[provider] {
        case .failed(let message): return message
        case .loading: return l10n.t("settings.provider.loadingModels")
        case .loaded:
            return modelOptions(for: provider, task: task).isEmpty
                ? l10n.t("settings.provider.noModels")
                : l10n.t("settings.provider.refreshModelsHint")
        case .idle, .none:
            let hasKey = !(viewModel.providerDrafts[provider]?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return hasKey
                ? l10n.t("settings.provider.refreshModelsHint")
                : l10n.t("settings.provider.modelsNeedKey")
        }
    }

    private func modelCatalogStatus(for provider: LLMProviderKind, task: LLMTask) -> String? {
        switch viewModel.modelCatalogs[provider] {
        case .failed(let message): return message
        case .loading: return l10n.t("settings.provider.loadingModels")
        case .loaded:
            return modelOptions(for: provider, task: task).isEmpty
                ? l10n.t("settings.provider.noModels")
                : nil
        case .idle: return modelCatalogMessage(for: provider, task: task)
        case .none: return nil
        }
    }

    private func invalidateModelCatalog(for provider: LLMProviderKind) {
        viewModel.invalidateModelCatalog(for: provider)
    }

    private func catalogInput(
        for provider: LLMProviderKind,
        drafts: [LLMProviderKind: ProviderDraft]
    ) -> ModelCatalogInput {
        let draft = drafts[provider]
        return ModelCatalogInput(
            apiKey: draft?.apiKey ?? "",
            customBaseURL: draft?.customBaseURL ?? "",
            qwenBaseURL: draft?.qwenBaseURL ?? "",
            mimoCluster: draft?.mimoCluster ?? .cn
        )
    }

    // MARK: Helpers


    private func providerName(_ provider: LLMProviderKind) -> String {
        switch provider {
        case .gemini: return "Gemini"
        case .qwen: return "Qwen"
        case .deepseek: return "DeepSeek"
        case .mimo: return "MiMo"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    private func taskName(_ task: LLMTask) -> String {
        switch task {
        case .translation: return l10n.t("settings.provider.task.translation")
        case .deepRead: return l10n.t("settings.provider.task.deepRead")
        case .grammar: return l10n.t("settings.provider.task.grammar")
        }
    }

    private func taskRouteHint(_ task: LLMTask) -> String {
        switch task {
        case .translation: return l10n.t("settings.provider.translationRouteHint")
        case .deepRead: return l10n.t("settings.provider.deepReadRouteHint")
        case .grammar: return l10n.t("settings.provider.grammarRouteHint")
        }
    }

    private func modelAccessibilityLabel(_ task: LLMTask) -> String {
        switch task {
        case .translation: return l10n.t("settings.provider.translationModel")
        case .deepRead: return l10n.t("settings.provider.deepReadModel")
        case .grammar: return l10n.t("settings.provider.grammarModel")
        }
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

    private func modelPlaceholder(for provider: LLMProviderKind, task: LLMTask) -> String {
        let defaultModel = provider.defaultModel(for: task)
        if !defaultModel.isEmpty { return defaultModel }
        return provider == .qwen && task != .translation ? "qwen-plus" : "model-id"
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

    private var validateButtonTitle: String {
        l10n.t("settings.provider.validateTaskButton", taskName(viewModel.validationTask))
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

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
