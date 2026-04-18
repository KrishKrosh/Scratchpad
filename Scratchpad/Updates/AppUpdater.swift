import Foundation
import Combine
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case available(version: String)
        case downloading(version: String, progress: Double?)
        case readyToInstall(version: String)
        case installing(version: String)
        case failed(message: String)
    }

    @Published private(set) var phase: Phase = .idle

    var isVisible: Bool {
        switch phase {
        case .available, .downloading, .readyToInstall, .installing:
            return true
        case .idle, .checking, .failed:
            return false
        }
    }

    var buttonTitle: String {
        switch phase {
        case .available:
            return "Update"
        case .downloading(_, let progress):
            if let progress {
                return "Updating \(Int(progress * 100))%"
            }
            return "Updating"
        case .readyToInstall:
            return "Update"
        case .installing:
            return "Installing"
        case .failed:
            return "Update"
        case .idle, .checking:
            return "Update"
        }
    }

    var isBusy: Bool {
        switch phase {
        case .downloading, .installing, .checking:
            return true
        case .idle, .available, .readyToInstall, .failed:
            return false
        }
    }

    private var updater: SPUUpdater?
    private var bytesDownloaded: UInt64 = 0
    private var expectedContentLength: UInt64?
    private var currentVersion: String?
    private var primaryAction: (() -> Void)?
    private var cancelAction: (() -> Void)?

    override init() {
        super.init()

        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: self,
            delegate: self
        )
        self.updater = updater

        do {
            try updater.start()
            if updater.automaticallyChecksForUpdates {
                phase = .checking
                updater.checkForUpdatesInBackground()
            }
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }

    func checkForUpdates() {
        guard let updater else { return }
        phase = .checking
        updater.checkForUpdates()
    }

    func triggerPrimaryAction() {
        primaryAction?()
    }

    func cancelCurrentAction() {
        cancelAction?()
    }

    private func setAvailableUpdate(_ item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let version = item.displayVersionString
        currentVersion = version

        switch state.stage {
        case .notDownloaded:
            phase = .available(version: version)
        case .downloaded:
            phase = .readyToInstall(version: version)
        case .installing:
            phase = .installing(version: version)
        @unknown default:
            phase = .available(version: version)
        }

        primaryAction = { reply(.install) }
        cancelAction = { reply(.dismiss) }
    }

    private func fail(_ error: Error) {
        phase = .failed(message: error.localizedDescription)
        primaryAction = { [weak self] in
            self?.checkForUpdates()
        }
        cancelAction = nil
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        fail(error)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if error == nil, case .checking = phase {
            phase = .idle
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        currentVersion = item.displayVersionString
        phase = .installing(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        currentVersion = item.displayVersionString
        phase = .readyToInstall(version: item.displayVersionString)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        phase = .available(version: currentVersion ?? "Update")
    }
}

extension AppUpdater: SPUUserDriver {
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        phase = .checking
        cancelAction = cancellation
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(
            automaticUpdateChecks: true,
            automaticUpdateDownloading: true,
            sendSystemProfile: false
        ))
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        setAvailableUpdate(appcastItem, state: state, reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        phase = .idle
        currentVersion = nil
        primaryAction = nil
        cancelAction = nil
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        fail(error)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        cancelAction = cancellation
        if case .available(let version) = phase {
            phase = .downloading(version: version, progress: nil)
        }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.expectedContentLength = expectedContentLength
        self.bytesDownloaded = 0
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        bytesDownloaded += length
        guard case .downloading(let version, _) = phase else { return }
        guard let expectedContentLength, expectedContentLength > 0 else {
            phase = .downloading(version: version, progress: nil)
            return
        }
        let progress = min(1, Double(bytesDownloaded) / Double(expectedContentLength))
        phase = .downloading(version: version, progress: progress)
    }

    func showDownloadDidStartExtractingUpdate() {}

    func showExtractionReceivedProgress(_ progress: Double) {
        guard case .downloading(let version, _) = phase else { return }
        phase = .downloading(version: version, progress: progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let version = currentVersion ?? "Update"
        phase = .readyToInstall(version: version)
        primaryAction = { reply(.install) }
        cancelAction = { reply(.dismiss) }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        phase = .idle
        currentVersion = nil
        primaryAction = nil
        cancelAction = nil
        acknowledgement()
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        let version = currentVersion ?? "Update"
        phase = .installing(version: version)
        primaryAction = applicationTerminated ? nil : retryTerminatingApplication
        cancelAction = nil
    }

    func dismissUpdateInstallation() {
        phase = .idle
        currentVersion = nil
        primaryAction = nil
        cancelAction = nil
    }

    func showUpdateInFocus() {}
}
