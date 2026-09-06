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

private struct ProviderDraft: Equatable, Sendable {
    var models: [LLMTask: String]
    var apiKey: String
    var customBaseURL: String
    var qwenBaseURL: String
    var mimoCluster: MiMoCluster

    init(provider: LLMProviderKind, settings: SettingsStore) {
        models = Dictionary(uniqueKeysWithValues: LLMTask.allCases.map {
            ($0, settings.model(for: provider, task: $0))
        })
        apiKey = KeychainStore.shared.apiKey(for: provider) ?? ""
        customBaseURL = settings.customBaseURL
        qwenBaseURL = settings.qwenBaseURL
        mimoCluster = settings.mimoCluster
    }

    func model(for task: LLMTask) -> String {
        models[task] ?? ""
    }

    mutating func setModel(_ model: String, for task: LLMTask) {
        models[task] = model
    }
}

private struct ModelCatalogInput: Equatable {
    let apiKey: String
    let customBaseURL: String
    let qwenBaseURL: String
    let mimoCluster: MiMoCluster
}

private enum ModelCatalogState: Equatable {
    case idle
    case loading
    case loaded([LLMModel])
    case failed(String)
}

/// Four-pane settings surface.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var l10n: L10n
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTab: SettingsTab = .general
    @State private var accessibilityGranted = SelectionReader.isAccessibilityGranted

    // Provider editor state is loaded only when Settings opens.
    @State private var routeProviders: [LLMTask: LLMProviderKind]
    @State private var credentialProvider: LLMProviderKind
    @State private var isAPIKeyVisible = false
    @State private var providerDrafts: [LLMProviderKind: ProviderDraft]
    @State private var originalAPIKeys: [LLMProviderKind: String]
    @State private var modelCatalogs: [LLMProviderKind: ModelCatalogState] = [:]
    @State private var catalogRequestIDs: [LLMProviderKind: UUID] = [:]
    @State private var validationTask: LLMTask = .translation
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var validationSucceeded = false
    @State private var saveMessage: String?

    init() {
        let settings = SettingsStore.shared
        let routes = Dictionary(uniqueKeysWithValues: LLMTask.allCases.map {
            ($0, settings.toolPanelProvider(for: $0))
        })
        let drafts = Dictionary(uniqueKeysWithValues: LLMProviderKind.allCases.map {
            ($0, ProviderDraft(provider: $0, settings: settings))
        })
        _routeProviders = State(initialValue: routes)
        _credentialProvider = State(initialValue: routes[.translation] ?? .gemini)
        _providerDrafts = State(initialValue: drafts)
        _originalAPIKeys = State(initialValue: drafts.mapValues(\.apiKey))
        let translationProvider = routes[.translation] ?? .gemini
        let translationModel = drafts[translationProvider]?.model(for: .translation) ?? ""
        _validationTask = State(
            initialValue: translationModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .grammar
                : .translation
        )
    }

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

    // MARK: General

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.ink.opacity(0.035))
            )
    }

    private var generalPane: some View {
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
                                    Button(l10n.t("settings.permissions.grant")) {
                                        requestAccessibility()
                                    }
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
            for provider in Set(routeProviders.values) {
                ensureModelsLoaded(for: provider)
            }
        }
        .onChange(of: routeProviders) { oldRoutes, newRoutes in
            for task in LLMTask.allCases {
                guard oldRoutes[task] != newRoutes[task], let provider = newRoutes[task] else { continue }
                ensureModelsLoaded(for: provider)
            }
        }
        .onChange(of: providerDrafts) { oldDrafts, newDrafts in
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
                ProviderIcon(provider: credentialProvider, size: 16)
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
                    title: providerName(credentialProvider),
                    options: LLMProviderKind.allCases,
                    label: { providerName($0) },
                    isSelected: { $0 == credentialProvider },
                    width: 176,
                    accessibilityLabel: l10n.t("settings.provider.editProvider"),
                    onSelect: {
                        credentialProvider = $0
                        isAPIKeyVisible = false
                    }
                )
            }
            .padding(12)
            providerDivider

            if credentialProvider == .custom {
                providerField(l10n.t("settings.provider.baseURL")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(
                            "https://api.example.com/v1",
                            text: draftBinding(credentialProvider, keyPath: \.customBaseURL)
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

            if credentialProvider == .qwen {
                providerField(l10n.t("settings.provider.baseURL")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(
                            QwenService.defaultBaseURL,
                            text: draftBinding(credentialProvider, keyPath: \.qwenBaseURL)
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

            if credentialProvider == .mimo {
                providerField(l10n.t("settings.provider.cluster")) {
                    let cluster = draftBinding(credentialProvider, keyPath: \.mimoCluster)
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
                                text: draftBinding(credentialProvider, keyPath: \.apiKey)
                            )
                        } else {
                            SecureField(
                                "••••••••••••••••",
                                text: draftBinding(credentialProvider, keyPath: \.apiKey)
                            )
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(l10n.t("settings.provider.apiKey"))
                    .onSubmit {
                        refreshModels(for: credentialProvider)
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
                Text(endpointLabel(for: credentialProvider))
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
                    .help(endpointLabel(for: credentialProvider))
            }
            providerDivider

            providerHelp(for: credentialProvider)
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
                if case .loading = modelCatalogs[provider] {
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
                if case .loading = modelCatalogs[provider] { return true }
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
            if let validationMessage {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: validationSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(validationSucceeded ? Theme.fixed : Theme.wrong)
                    Text(validationMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let saveMessage {
                Label(saveMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.fixed)
            }

            Spacer(minLength: 12)

            ThemedMenu(
                title: taskName(validationTask),
                options: LLMTask.allCases,
                label: { taskName($0) },
                isSelected: { $0 == validationTask },
                width: 132,
                accessibilityLabel: l10n.t("settings.provider.validateTask"),
                onSelect: { validationTask = $0 }
            )

            Button(l10n.t("settings.provider.save")) {
                persistProvider(showFeedback: true)
            }
            Button(isValidating ? l10n.t("settings.provider.validating") : validateButtonTitle) {
                validateProvider()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(isValidating)
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

    // MARK: Shortcuts

    private var shortcutsPane: some View {
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

    // MARK: About

    private var aboutPane: some View {
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

    // MARK: Provider actions

    private func persistProvider(showFeedback: Bool) {
        let settings = SettingsStore.shared
        for provider in LLMProviderKind.allCases {
            guard let draft = providerDrafts[provider] else { continue }
            for task in LLMTask.allCases {
                settings.setModel(
                    draft.model(for: task).trimmingCharacters(in: .whitespacesAndNewlines),
                    for: provider,
                    task: task
                )
            }
            let normalizedKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedKey != originalAPIKeys[provider] {
                KeychainStore.shared.setAPIKey(normalizedKey, for: provider)
            }
        }
        if let custom = providerDrafts[.custom] {
            settings.customBaseURL = custom.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let qwen = providerDrafts[.qwen] {
            settings.qwenBaseURL = qwen.qwenBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let mimo = providerDrafts[.mimo] {
            settings.mimoCluster = mimo.mimoCluster
            MiMoService.shared.setCluster(mimo.mimoCluster)
        }
        for task in LLMTask.allCases {
            settings.setToolPanelProvider(routeProvider(for: task), for: task)
        }
        originalAPIKeys = providerDrafts.mapValues { $0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
        appState.toolPanelModel.refreshConfiguration()
        for provider in Set(routeProviders.values) {
            ensureModelsLoaded(for: provider)
        }
        if showFeedback {
            saveMessage = l10n.t("settings.provider.saved")
            validationMessage = nil
        }
    }

    private func validateProvider() {
        persistProvider(showFeedback: false)
        isValidating = true
        validationMessage = nil
        validationSucceeded = false
        saveMessage = nil

        let provider = routeProvider(for: validationTask)
        Task { @MainActor in
            do {
                let resolved = try ProviderResolver.resolve(provider, task: validationTask)
                let endpoint = try await resolved.service.validate(
                    apiKey: resolved.apiKey,
                    model: resolved.model
                )
                validationMessage = l10n.t("provider.connected", endpoint)
                validationSucceeded = true
            } catch {
                validationMessage = l10n.errorText(error)
                validationSucceeded = false
            }
            isValidating = false
        }
    }

    private func draftBinding<Value>(
        _ provider: LLMProviderKind,
        keyPath: WritableKeyPath<ProviderDraft, Value>
    ) -> Binding<Value> {
        Binding(
            get: { providerDrafts[provider]![keyPath: keyPath] },
            set: { value in
                guard var draft = providerDrafts[provider] else { return }
                draft[keyPath: keyPath] = value
                providerDrafts[provider] = draft
            }
        )
    }

    private func routeProvider(for task: LLMTask) -> LLMProviderKind {
        routeProviders[task] ?? .gemini
    }

    private func routeBinding(for task: LLMTask) -> Binding<LLMProviderKind> {
        Binding(
            get: { routeProvider(for: task) },
            set: { routeProviders[task] = $0 }
        )
    }

    private func draftModel(for provider: LLMProviderKind, task: LLMTask) -> String {
        providerDrafts[provider]?.model(for: task)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func modelBinding(for provider: LLMProviderKind, task: LLMTask) -> Binding<String> {
        Binding(
            get: { providerDrafts[provider]?.model(for: task) ?? "" },
            set: { model in
                guard var draft = providerDrafts[provider] else { return }
                draft.setModel(model, for: task)
                providerDrafts[provider] = draft
            }
        )
    }

    private func setModel(_ model: String, for provider: LLMProviderKind, task: LLMTask) {
        modelBinding(for: provider, task: task).wrappedValue = model
    }

    private func ensureModelsLoaded(for provider: LLMProviderKind) {
        switch modelCatalogs[provider] {
        case .loading, .loaded:
            return
        default:
            break
        }
        refreshModels(for: provider)
    }

    private func refreshModels(for provider: LLMProviderKind) {
        let requestID = UUID()
        catalogRequestIDs[provider] = requestID
        let key = providerDrafts[provider]?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            modelCatalogs[provider] = .failed(l10n.t("settings.provider.modelsNeedKey"))
            return
        }

        modelCatalogs[provider] = .loading
        let service = catalogService(for: provider)

        Task { @MainActor in
            do {
                let models = try await service.listModels(apiKey: key)
                guard catalogRequestIDs[provider] == requestID else { return }
                modelCatalogs[provider] = .loaded(normalizeModels(models))
            } catch {
                guard catalogRequestIDs[provider] == requestID else { return }
                modelCatalogs[provider] = .failed(l10n.errorText(error))
            }
        }
    }

    private func catalogService(for provider: LLMProviderKind) -> any LLMServicing {
        let draft = providerDrafts[provider]!
        switch provider {
        case .gemini:
            return GeminiService()
        case .deepseek:
            return DeepSeekService()
        case .mimo:
            let service = MiMoService()
            service.setCluster(draft.mimoCluster)
            return service
        case .qwen:
            let service = QwenService()
            let base = draft.qwenBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            service.baseURLProvider = {
                base.isEmpty ? QwenService.defaultBaseURL : base
            }
            return service
        case .custom:
            let service = CustomService()
            let base = draft.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            service.baseURLProvider = { base }
            return service
        }
    }

    private func normalizeModels(_ models: [LLMModel]) -> [LLMModel] {
        var seen = Set<String>()
        return models
            .compactMap { model in
                let id = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, seen.insert(id).inserted else { return nil }
                return LLMModel(id: id, displayName: model.displayName, description: model.description)
            }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private func modelOptions(
        for provider: LLMProviderKind,
        task: LLMTask
    ) -> [LLMModel] {
        let catalog: [LLMModel]
        if case .loaded(let loaded) = modelCatalogs[provider] {
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
        switch modelCatalogs[provider] {
        case .failed(let message): return message
        case .loading: return l10n.t("settings.provider.loadingModels")
        case .loaded:
            return modelOptions(for: provider, task: task).isEmpty
                ? l10n.t("settings.provider.noModels")
                : l10n.t("settings.provider.refreshModelsHint")
        case .idle, .none:
            let hasKey = !(providerDrafts[provider]?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return hasKey
                ? l10n.t("settings.provider.refreshModelsHint")
                : l10n.t("settings.provider.modelsNeedKey")
        }
    }

    private func modelCatalogStatus(for provider: LLMProviderKind, task: LLMTask) -> String? {
        switch modelCatalogs[provider] {
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
        catalogRequestIDs[provider] = UUID()
        modelCatalogs[provider] = .idle
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

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .textCase(.uppercase)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func requestAccessibility() {
        accessibilityGranted = SelectionReader.promptForAccessibilityIfNeeded()
        if !accessibilityGranted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
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
        let draft = providerDrafts[provider]!
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
        l10n.t("settings.provider.validateTaskButton", taskName(validationTask))
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
