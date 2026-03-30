import Combine
import Foundation
import Observation
import Sparkle

@Observable
@MainActor
final class AppUpdater {
    var canCheckForUpdates = false
    var isConfigured = false

    private let updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: AnyCancellable?
    private var hasStarted = false

    init(bundle: Bundle = .main) {
        let feedURL = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publicKey = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let configured = !feedURL.isEmpty && !publicKey.isEmpty

        isConfigured = configured

        guard configured else {
            updaterController = nil
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        canCheckObservation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
    }

    func start() {
        guard isConfigured, !hasStarted, let updaterController else { return }
        hasStarted = true
        updaterController.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates, let updaterController else { return }
        updaterController.checkForUpdates(nil)
    }
}
