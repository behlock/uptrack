import Foundation
import GRDB
import Observation
import os

/// Always-current list of recent tracks for the menu and bezel, driven by a
/// GRDB ValueObservation — no manual reloads or invalidation hooks needed.
@MainActor
@Observable
final class TrackHistoryStore {
    private(set) var tracks: [BezelTrackItem] = []

    @ObservationIgnored private var observationTask: Task<Void, Never>?

    init(database: DatabaseManager) {
        observationTask = Task { [weak self] in
            do {
                for try await tracks in database.recentTracksSequence(limit: Constants.recentTrackLimit) {
                    guard let self else { return }
                    self.tracks = tracks
                }
            } catch {
                Logger.database.error("Track observation failed: \(error)")
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }
}
