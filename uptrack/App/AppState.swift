import KeyboardShortcuts
import Observation
import os
import SwiftUI

@MainActor
@Observable
final class AppState {
    let mediaRemoteAvailable = MediaRemoteBridge.isAvailable
    private(set) var databaseAvailable = true

    let databaseManager: DatabaseManager?
    let trackStore: TrackHistoryStore?
    let sessionManager: SessionManager?
    let bezelController: BezelController?
    private let nowPlayingMonitor: NowPlayingMonitor?
    private let audioDeviceMonitor: AudioDeviceMonitor

    init() {
        Logger.app.debug("init starting...")
        audioDeviceMonitor = AudioDeviceMonitor()

        do {
            let db = try DatabaseManager()
            databaseManager = db
            Logger.app.debug("Database initialized")

            let store = TrackHistoryStore(database: db)
            trackStore = store

            let sm = SessionManager(database: db)
            sessionManager = sm

            let npm = NowPlayingMonitor(
                sessionManager: sm,
                audioDeviceMonitor: audioDeviceMonitor
            )
            nowPlayingMonitor = npm

            npm.start()
            audioDeviceMonitor.startMonitoring()
            Logger.app.debug("Monitors started")

            bezelController = BezelController(trackStore: store)
        } catch {
            Logger.app.error("Failed to initialize database: \(error)")
            databaseManager = nil
            trackStore = nil
            sessionManager = nil
            nowPlayingMonitor = nil
            bezelController = nil
            databaseAvailable = false
        }

        KeyboardShortcuts.onKeyDown(for: .showBezel) { [weak self] in
            self?.bezelController?.show()
        }
    }

    /// Release system-level resources (notification observers, CoreAudio listeners, hotkeys).
    /// Intended to be called from AppDelegate.applicationWillTerminate.
    func shutdown() {
        nowPlayingMonitor?.stop()
        audioDeviceMonitor.stopMonitoring()
        KeyboardShortcuts.disable(.showBezel)
    }
}
