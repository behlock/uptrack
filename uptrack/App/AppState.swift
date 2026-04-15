import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var currentSession: PlaybackSession?
    @Published var currentTrack: TrackEntry?
    @Published var isPlaying: Bool = false
    @Published var mediaRemoteAvailable: Bool = true
    @Published var databaseAvailable: Bool = true

    let databaseManager: DatabaseManager?
    let nowPlayingMonitor: NowPlayingMonitor?
    let audioDeviceMonitor: AudioDeviceMonitor
    let sessionManager: SessionManager?
    let hotkeyManager: HotkeyManager
    let bezelController: BezelController?

    init() {
        debugLog("[AppState] init starting...")
        audioDeviceMonitor = AudioDeviceMonitor()

        do {
            let db = try DatabaseManager()
            databaseManager = db
            debugLog("[AppState] Database initialized")

            let sm = SessionManager(database: db)
            sessionManager = sm
            debugLog("[AppState] SessionManager initialized")

            let npm = NowPlayingMonitor(
                sessionManager: sm,
                audioDeviceMonitor: audioDeviceMonitor
            )
            nowPlayingMonitor = npm

            npm.start()
            debugLog("[AppState] NowPlayingMonitor started")
            audioDeviceMonitor.startMonitoring()
            debugLog("[AppState] AudioDeviceMonitor started")

            mediaRemoteAvailable = MediaRemoteBridge.isAvailable

            // Bezel browsing
            let bc = BezelController(databaseManager: db)
            bezelController = bc
            let hk = HotkeyManager()
            hotkeyManager = hk
            hk.onHotkeyActivated = { [weak self] in self?.bezelController?.show() }
            hk.start()

            // Bind session manager state to app state
            observeSessionManager(sm)
        } catch {
            debugLog("[AppState] Failed to initialize database: \(error)")
            databaseManager = nil
            sessionManager = nil
            nowPlayingMonitor = nil
            bezelController = nil
            hotkeyManager = HotkeyManager()
            databaseAvailable = false
        }
    }

    private func observeSessionManager(_ sm: SessionManager) {
        sm.$currentSession.assign(to: &$currentSession)
        sm.$currentTrack.assign(to: &$currentTrack)
        sm.$isPlaying.assign(to: &$isPlaying)
    }

    /// Release system-level resources (notification observers, CoreAudio listeners, hotkeys).
    /// Intended to be called from AppDelegate.applicationWillTerminate.
    func shutdown() {
        nowPlayingMonitor?.stop()
        audioDeviceMonitor.stopMonitoring()
        hotkeyManager.stop()
    }
}
