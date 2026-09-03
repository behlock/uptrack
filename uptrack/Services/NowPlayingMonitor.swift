import AppKit
import Foundation
import os

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

@MainActor
final class NowPlayingMonitor {
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
    private var isMediaRemotePrimary: Bool {
        primarySource == .mediaRemote
    }

    /// Last (title, artist) we kicked off an artwork fetch for on the distributed
    /// path. Distributed notifications fire on every play/pause/scrub, so we dedupe
    /// here to avoid hammering the source app's AppleScript bridge.
    private var lastArtworkFetchKey: String?

    /// Bundle id / name of the app MediaRemote reports as now-playing.
    private var mrAppBundleId: String?
    private var mrAppName: String?

    init(sessionManager: SessionManager, audioDeviceMonitor: AudioDeviceMonitor) {
        self.sessionManager = sessionManager
        self.audioDeviceMonitor = audioDeviceMonitor
    }

    func start() {
        Logger.nowPlaying.debug("Starting...")

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

        // `DistributedMediaInfo.knownApps` is the single source of truth for which
        // player notifications we understand.
        for rawName in DistributedMediaInfo.knownApps.keys.sorted() {
            let name = NSNotification.Name(rawName)
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
            Logger.nowPlaying.debug("Registered distributed notification: \(rawName)")
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

        Logger.nowPlaying.debug("Distributed: \(info.appName) | \(info.title ?? "nil") - \(info.artist ?? "nil") | state: \(info.playerState ?? "nil") | duration: \(info.durationSeconds ?? -1)")

        sessionManager.handleNowPlayingUpdate(
            NowPlayingUpdate(
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
            ),
            device: audioDeviceMonitor.currentDevice
        )

        fetchArtworkForDistributedTrack(info)
    }

    /// On macOS 26+ MediaRemote no longer exposes artwork to third parties, so the
    /// distributed-notification path passes `nil` above. Compensate by asking the
    /// source app directly via AppleScript and patching the artwork in once the
    /// track row exists. Only runs when the (title, artist) pair changes so we
    /// don't re-fetch on play/pause/scrub; a failed fetch clears the key so the
    /// next event for the same track retries.
    private func fetchArtworkForDistributedTrack(_ info: DistributedMediaInfo) {
        guard info.isPlaying, info.title != nil || info.artist != nil else { return }
        let key = "\(info.title ?? "")|\(info.artist ?? "")"
        guard key != lastArtworkFetchKey else { return }
        lastArtworkFetchKey = key

        let title = info.title
        let artist = info.artist
        let bundleId = info.bundleId
        Task { [weak self] in
            guard let data = await ArtworkFetcher.fetch(bundleId: bundleId) else {
                if self?.lastArtworkFetchKey == key {
                    self?.lastArtworkFetchKey = nil
                }
                return
            }
            self?.sessionManager.patchCurrentTrackArtwork(data, title: title, artist: artist)
        }
    }

    // MARK: - MediaRemote (works on macOS <26)

    private func startMediaRemote() {
        guard MediaRemoteBridge.isAvailable else {
            Logger.nowPlaying.debug("MediaRemote framework not available")
            return
        }

        Logger.nowPlaying.debug("MediaRemote available, attempting registration...")
        MediaRemoteBridge.registerForNowPlayingNotifications?(DispatchQueue.main)

        // Always register observers — they'll start firing when playback begins
        registerMediaRemoteObservers()

        // Initial probe. Resolve the now-playing app *before* reading its info so a
        // session started from this probe is attributed to the right app instead of
        // "Unknown App" (which would then be closed and replaced on the next event).
        handleMediaRemoteAppChange()
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

    private func handleMediaRemoteAppChange() {
        guard let getPID = MediaRemoteBridge.getNowPlayingApplicationPID else {
            fetchMediaRemoteInfo()
            return
        }
        getPID(DispatchQueue.main) { [weak self] pid in
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
            Logger.nowPlaying.debug("MediaRemote now returning data — using as primary source, suppressing distributed notifications")
            primarySource = .mediaRemote
        }

        let bundleId = mrAppBundleId ?? "unknown"
        let appName = mrAppName ?? "Unknown App"

        sessionManager.handleNowPlayingUpdate(
            NowPlayingUpdate(
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
            ),
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
