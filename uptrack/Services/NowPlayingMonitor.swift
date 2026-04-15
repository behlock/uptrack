import AppKit
import Foundation

private struct MRParsedInfo: Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let durationSeconds: Double?
    let elapsedSeconds: Double?
    let playbackRate: Double

    static func extract(from info: [String: Any]) -> MRParsedInfo {
        MRParsedInfo(
            title: info[MediaRemoteBridge.infoTitle] as? String,
            artist: info[MediaRemoteBridge.infoArtist] as? String,
            album: info[MediaRemoteBridge.infoAlbum] as? String,
            artworkData: info[MediaRemoteBridge.infoArtworkData] as? Data,
            durationSeconds: info[MediaRemoteBridge.infoDuration] as? Double,
            elapsedSeconds: info[MediaRemoteBridge.infoElapsedTime] as? Double,
            playbackRate: info[MediaRemoteBridge.infoPlaybackRate] as? Double ?? 0.0
        )
    }
}

private struct DistributedMediaInfo: Sendable {
    let bundleId: String
    let appName: String
    let title: String?
    let artist: String?
    let album: String?
    let playerState: String?
    let durationSeconds: Double?
    let elapsedSeconds: Double?
    let trackURI: String?

    var isPlaying: Bool { playerState == "Playing" }

    static let knownApps: [String: (bundleId: String, name: String)] = [
        "com.spotify.client.PlaybackStateChanged": ("com.spotify.client", "Spotify"),
        "com.apple.Music.playerInfo": ("com.apple.Music", "Music"),
        "com.apple.iTunes.playerInfo": ("com.apple.Music", "Music"),
    ]

    static func parse(_ notification: Notification) -> DistributedMediaInfo {
        let userInfo = notification.userInfo ?? [:]
        let notifName = notification.name.rawValue
        let appInfo = knownApps[notifName]

        let title = truncateMetadata(userInfo["Name"] as? String)
        let artist = truncateMetadata(userInfo["Artist"] as? String)
        let album = truncateMetadata(userInfo["Album"] as? String)
        let playerState = userInfo["Player State"] as? String

        var durationSeconds: Double?
        if let d = userInfo["Duration"] as? Int { durationSeconds = Double(d) / 1000.0 }
        else if let d = userInfo["Duration"] as? Double { durationSeconds = d / 1000.0 }
        else if let d = userInfo["Total Time"] as? Int { durationSeconds = Double(d) / 1000.0 }
        else if let d = userInfo["Total Time"] as? Double { durationSeconds = d / 1000.0 }

        var elapsedSeconds: Double?
        if let p = userInfo["Playback Position"] as? Double { elapsedSeconds = p }
        else if let p = userInfo["Player Position"] as? Double { elapsedSeconds = p }

        let trackURI = truncateMetadata(userInfo["Track ID"] as? String)

        return DistributedMediaInfo(
            bundleId: appInfo?.bundleId ?? "unknown",
            appName: appInfo?.name ?? "Unknown App",
            title: title,
            artist: artist,
            album: album,
            playerState: playerState,
            durationSeconds: durationSeconds,
            elapsedSeconds: elapsedSeconds,
            trackURI: trackURI
        )
    }
}

struct NowPlayingInfo: Sendable {
    let appBundleId: String
    let appName: String
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let durationSeconds: Double?
    let elapsedSeconds: Double?
    let isPlaying: Bool
    let trackURI: String?
}

@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published var latestInfo: NowPlayingInfo?

    private let sessionManager: SessionManager
    private let audioDeviceMonitor: AudioDeviceMonitor

    private enum ObserverCenter {
        case `default`, distributed, workspace
    }
    private var observations: [(center: ObserverCenter, token: NSObjectProtocol)] = []

    /// Which metadata source is currently authoritative.
    ///
    /// Transitions are one-way: `.awaitingProbe` → `.mediaRemote` the first time MediaRemote
    /// delivers real data. Once we've committed to MediaRemote we never fall back, and
    /// distributed notifications are demoted to URI-only patching (they carry Spotify's
    /// `spotify:track:*` URI which MediaRemote does not expose).
    ///
    /// All reads and writes happen on `@MainActor`, so there is no concurrent access.
    private enum PrimarySource {
        case awaitingProbe
        case mediaRemote
    }
    private var primarySource: PrimarySource = .awaitingProbe
    private var isMediaRemotePrimary: Bool { primarySource == .mediaRemote }

    // Known distributed notification names from media players
    private static let spotifyNotification = NSNotification.Name("com.spotify.client.PlaybackStateChanged")
    private static let musicNotification = NSNotification.Name("com.apple.Music.playerInfo")
    private static let itunesNotification = NSNotification.Name("com.apple.iTunes.playerInfo")

    init(sessionManager: SessionManager, audioDeviceMonitor: AudioDeviceMonitor) {
        self.sessionManager = sessionManager
        self.audioDeviceMonitor = audioDeviceMonitor
    }

    func start() {
        debugLog("[NowPlayingMonitor] Starting...")

        // Try MediaRemote first — will work on macOS <26
        startMediaRemote()

        // Always register distributed notifications as fallback (works on all macOS versions)
        startDistributedNotifications()

        // Sleep/wake observers
        startSleepWakeObservers()
    }

    func stop() {
        for (center, token) in observations {
            switch center {
            case .default:
                NotificationCenter.default.removeObserver(token)
            case .distributed:
                DistributedNotificationCenter.default().removeObserver(token)
            case .workspace:
                NSWorkspace.shared.notificationCenter.removeObserver(token)
            }
        }
        observations.removeAll()
    }

    // MARK: - Distributed Notifications (primary on macOS 26+)

    private func startDistributedNotifications() {
        let dnc = DistributedNotificationCenter.default()

        let notifNames: [NSNotification.Name] = [
            Self.spotifyNotification,
            Self.musicNotification,
            Self.itunesNotification,
        ]

        for name in notifNames {
            let obs = dnc.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                // Extract all values on this thread before crossing isolation boundary
                let parsed = DistributedMediaInfo.parse(notification)
                Task { @MainActor in
                    self?.handleDistributedMediaInfo(parsed)
                }
            }
            observations.append((.distributed, obs))
            debugLog("[NowPlayingMonitor] Registered distributed notification: \(name.rawValue)")
        }
    }

    private func handleDistributedMediaInfo(_ info: DistributedMediaInfo) {
        // Once MediaRemote is the authoritative source, distributed notifications are
        // used only to patch in the Spotify track URI — MediaRemote doesn't surface it.
        if isMediaRemotePrimary {
            if let uri = info.trackURI, !uri.isEmpty {
                sessionManager.patchCurrentTrackURI(uri)
            }
            return
        }

        debugLog("[NowPlayingMonitor] Distributed: \(info.appName) | \(info.title ?? "nil") - \(info.artist ?? "nil") | state: \(info.playerState ?? "nil") | duration: \(info.durationSeconds ?? -1)")

        let nowPlaying = NowPlayingInfo(
            appBundleId: info.bundleId,
            appName: info.appName,
            title: info.title,
            artist: info.artist,
            album: info.album,
            artworkData: nil,
            durationSeconds: info.durationSeconds,
            elapsedSeconds: info.elapsedSeconds,
            isPlaying: info.isPlaying,
            trackURI: info.trackURI
        )

        latestInfo = nowPlaying

        sessionManager.handleNowPlayingUpdate(
            appBundleId: info.bundleId,
            appName: info.appName,
            title: info.title,
            artist: info.artist,
            album: info.album,
            artworkData: nil,
            duration: info.durationSeconds,
            elapsed: info.elapsedSeconds,
            isPlaying: info.isPlaying,
            trackURI: info.trackURI,
            device: audioDeviceMonitor.currentDevice
        )
    }

    // MARK: - MediaRemote (works on macOS <26)

    private func startMediaRemote() {
        guard MediaRemoteBridge.isAvailable else {
            debugLog("[NowPlayingMonitor] MediaRemote framework not available")
            return
        }

        debugLog("[NowPlayingMonitor] MediaRemote available, attempting registration...")
        MediaRemoteBridge.registerForNowPlayingNotifications?(DispatchQueue.main)

        // Always register observers — they'll start firing when playback begins
        registerMediaRemoteObservers()

        // Probe to check if MediaRemote is currently returning data
        MediaRemoteBridge.getNowPlayingInfo?(DispatchQueue.main) { [weak self] info in
            let hasData = !info.isEmpty
            let parsed = MRParsedInfo.extract(from: info)
            Task { @MainActor in
                guard let self else { return }
                if hasData {
                    debugLog("[NowPlayingMonitor] MediaRemote is returning data — using as primary source")
                    self.primarySource = .mediaRemote
                    self.processMediaRemoteParsed(parsed)
                } else {
                    debugLog("[NowPlayingMonitor] MediaRemote returned empty — will activate on first callback")
                }
            }
        }
    }

    private func registerMediaRemoteObservers() {
        let nc = NotificationCenter.default

        observations.append((.default, nc.addObserver(
            forName: MediaRemoteBridge.nowPlayingInfoDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.fetchMediaRemoteInfo() }
        }))

        observations.append((.default, nc.addObserver(
            forName: MediaRemoteBridge.nowPlayingApplicationDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleMediaRemoteAppChange() }
        }))

        observations.append((.default, nc.addObserver(
            forName: MediaRemoteBridge.nowPlayingApplicationIsPlayingDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.fetchMediaRemoteInfo() }
        }))
    }

    private var mrAppBundleId: String?
    private var mrAppName: String?

    private func handleMediaRemoteAppChange() {
        MediaRemoteBridge.getNowPlayingApplicationPID?(DispatchQueue.main) { [weak self] pid in
            Task { @MainActor in
                guard let self else { return }
                if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
                    self.mrAppBundleId = app.bundleIdentifier
                    self.mrAppName = app.localizedName
                }
                self.fetchMediaRemoteInfo()
            }
        }
    }

    private func fetchMediaRemoteInfo() {
        MediaRemoteBridge.getNowPlayingInfo?(DispatchQueue.main) { [weak self] info in
            let parsed = MRParsedInfo.extract(from: info)
            Task { @MainActor in
                guard let self else { return }
                self.processMediaRemoteParsed(parsed)
            }
        }
    }

    private func processMediaRemoteParsed(_ info: MRParsedInfo) {
        // Promote MediaRemote to primary the first time we see real metadata.
        if !isMediaRemotePrimary && (info.title != nil || info.artist != nil) {
            debugLog("[NowPlayingMonitor] MediaRemote now returning data — suppressing distributed notifications")
            primarySource = .mediaRemote
        }

        let bundleId = mrAppBundleId ?? "unknown"
        let appName = mrAppName ?? "Unknown App"

        let nowPlaying = NowPlayingInfo(
            appBundleId: bundleId,
            appName: appName,
            title: info.title,
            artist: info.artist,
            album: info.album,
            artworkData: info.artworkData,
            durationSeconds: info.durationSeconds,
            elapsedSeconds: info.elapsedSeconds,
            isPlaying: info.playbackRate > 0.0,
            trackURI: nil
        )

        latestInfo = nowPlaying

        sessionManager.handleNowPlayingUpdate(
            appBundleId: bundleId,
            appName: appName,
            title: info.title,
            artist: info.artist,
            album: info.album,
            artworkData: info.artworkData,
            duration: info.durationSeconds,
            elapsed: info.elapsedSeconds,
            isPlaying: info.playbackRate > 0.0,
            trackURI: nil,
            device: audioDeviceMonitor.currentDevice
        )
    }

    // MARK: - Sleep/Wake

    private func startSleepWakeObservers() {
        let wsnc = NSWorkspace.shared.notificationCenter

        observations.append((.workspace, wsnc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sessionManager.handleSleep()
            }
        }))

        observations.append((.workspace, wsnc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.isMediaRemotePrimary == true {
                    self?.handleMediaRemoteAppChange()
                }
                // Distributed notifications will fire naturally on wake
            }
        }))
    }
}
