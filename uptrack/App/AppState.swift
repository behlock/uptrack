import KeyboardShortcuts
import Observation
import os
import SwiftUI

@MainActor
@Observable
final class AppState {
    let mediaRemoteAvailable = MediaRemoteBridge.isAvailable
    let databaseAvailable: Bool

    let databaseManager: DatabaseManager?
    let trackStore: TrackHistoryStore?
    let sessionManager: SessionManager?
    let bezelController: BezelController?
    private let nowPlayingMonitor: NowPlayingMonitor?
    private let audioDeviceMonitor: AudioDeviceMonitor

    init() {
        Logger.app.debug("init starting...")
        audioDeviceMonitor = AudioDeviceMonitor()
        // Start device monitoring first so the initial output device is known
        // before the first now-playing update reaches the session manager.
        audioDeviceMonitor.startMonitoring()

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
            Logger.app.debug("Monitors started")

            bezelController = BezelController(trackStore: store)
            databaseAvailable = true
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
