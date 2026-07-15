import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class UpdaterController {
    private let controller: SPUStandardUpdaterController
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var observationTask: Task<Void, Never>?

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        let updater = controller.updater
        observationTask = Task { [weak self] in
            for await value in updater.publisher(for: \.canCheckForUpdates).values {
                guard let self else { return }
                self.canCheckForUpdates = value
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
