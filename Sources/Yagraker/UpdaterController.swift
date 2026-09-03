import Foundation
import Sparkle
import YagrakerCore

/// Wraps Sparkle's SPUStandardUpdaterController with an observable status
/// for the menu item and Settings pane.
@MainActor
final class UpdaterController: NSObject, ObservableObject {

    enum Status: Equatable {
        case idle
        case notConfigured
        case checking
        case upToDate
        case available(String)
        case failed(String)
    }

    private var controller: SPUStandardUpdaterController!
    private var isStarted = false
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastCheckedAt: Date?

    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            SettingsStore.shared.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    override init() {
        let stored = SettingsStore.shared.automaticallyChecksForUpdates
        automaticallyChecksForUpdates = stored
        lastCheckedAt = SettingsStore.shared.updatesLastCheckedAt
        super.init()

        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyChecksForUpdates = stored
        controller.updater.updateCheckInterval = 12 * 3600
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        guard let feed, let url = URL(string: feed), url.scheme != nil else {
            status = .notConfigured
            return
        }
        do {
            try controller.updater.start()
            isStarted = true
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// User-initiated check (menu / Settings button).
    func checkForUpdates() {
        guard isStarted else {
            status = .notConfigured
            return
        }
        status = .checking
        controller.checkForUpdates(nil)
    }

    /// Quiet background probe on launch — only surfaces UI when an update is ready.
    func runSilentProbe() {
        guard isStarted, automaticallyChecksForUpdates else { return }
        controller.updater.checkForUpdatesInBackground()
    }

    private func recordCompletedCheck() {
        lastCheckedAt = Date()
        SettingsStore.shared.updatesLastCheckedAt = lastCheckedAt
    }

    var menuTitle: String {
        let l10n = L10n.shared
        switch status {
        case .checking: return l10n.t("updater.menu.checking")
        case .available(let version): return l10n.t("updater.menu.updateTo", version)
        default: return l10n.t("updater.menu.check")
        }
    }

    var statusMessage: String {
        let l10n = L10n.shared
        switch status {
        case .idle: return l10n.t("updater.status.background")
        case .notConfigured: return l10n.t("updater.status.notConfigured")
        case .checking: return l10n.t("updater.status.checking")
        case .upToDate: return l10n.t("updater.status.upToDate")
        case .available(let version): return l10n.t("updater.status.available", version)
        case .failed(let message): return l10n.t("updater.status.failed", message)
        }
    }

    var isChecking: Bool { status == .checking }
    var canCheckForUpdates: Bool { isStarted }
}

// MARK: - SPUUpdaterDelegate (informational callbacks)

extension UpdaterController: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.status = .available(item.displayVersionString)
            self.recordCompletedCheck()
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.status = .upToDate
            self.recordCompletedCheck()
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Task { @MainActor in
            if self.status == .checking {
                self.status = .failed(error.localizedDescription)
            }
            self.recordCompletedCheck()
        }
    }
}
