import AppKit

/// Tracks the external application that owns the current selection and restores
/// focus after Yagraker's floating panels close.
@MainActor
final class ExternalAppContext {
    private(set) var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    init() {
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.rememberExternalApplication(application)
            }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func currentExternalApplication() -> NSRunningApplication? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            rememberExternalApplication(frontmost)
        }
        return lastExternalApplication
    }

    func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated else { return }
        lastExternalApplication = application
    }

    func restoreExternalApplicationIfNeeded() {
        guard !PopupWindow.isTestingEnvironment else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
                  NSApp.keyWindow == nil,
                  let application = self.lastExternalApplication,
                  !application.isTerminated else { return }
            application.activate(options: [])
        }
    }
}
