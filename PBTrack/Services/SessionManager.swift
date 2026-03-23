import AppKit
import Foundation

@MainActor
final class SessionManager: ObservableObject {
    @Published var currentSession: PlaybackSession?
    @Published var currentTrack: TrackEntry?
    @Published var isPlaying: Bool = false

    private let database: DatabaseManager
    private var pauseTimer: Timer?
    private var lastAppBundleId: String?
    private var lastDeviceUID: String?
    private var lastTrackTitle: String?
    private var lastTrackArtist: String?
    private var trackStartedAt: Date?

    init(database: DatabaseManager) {
        self.database = database

        // Close any sessions left active from a previous run
        do {
            try database.closeStaleActiveSessions()
        } catch {
            debugLog("[SessionManager] Failed to close stale sessions: \(error)")
        }
    }

    func handleNowPlayingUpdate(
        appBundleId: String,
        appName: String,
        title: String?,
        artist: String?,
        album: String?,
        artworkData: Data?,
        duration: Double?,
        elapsed: Double?,
        isPlaying: Bool,
        trackURI: String? = nil,
        device: AudioDevice
    ) {
        debugLog("[SessionManager] handleNowPlayingUpdate: \(appName) | \(title ?? "nil") - \(artist ?? "nil") | playing: \(isPlaying) | device: \(device.name)")
        self.isPlaying = isPlaying

        if !isPlaying {
            handlePause()
            return
        }

        // Cancel pause timer if resuming
        cancelPauseTimer()

        let appChanged = lastAppBundleId != nil && lastAppBundleId != appBundleId
        let deviceChanged = lastDeviceUID != nil && lastDeviceUID != device.uid

        if appChanged || deviceChanged {
            debugLog("[SessionManager] App/device changed, closing session")
            closeCurrentSession()
        }

        if currentSession == nil {
            debugLog("[SessionManager] Creating new session for \(appName)")
            startNewSession(
                appBundleId: appBundleId,
                appName: appName,
                device: device
            )
        }

        // Check if track changed
        let trackChanged = (title != lastTrackTitle || artist != lastTrackArtist)
            && (title != nil || artist != nil)

        if trackChanged || currentTrack == nil {
            debugLog("[SessionManager] Track changed: \(title ?? "nil") - \(artist ?? "nil"), saving...")
            finalizeCurrentTrack(elapsed: elapsed)
            startNewTrack(
                title: title,
                artist: artist,
                album: album,
                artworkData: artworkData,
                duration: duration,
                sourceURI: trackURI
            )
            debugLog("[SessionManager] Track saved, currentTrack id: \(currentTrack?.id ?? -1)")
        }

        lastAppBundleId = appBundleId
        lastDeviceUID = device.uid
        lastTrackTitle = title
        lastTrackArtist = artist
    }

    func handleSleep() {
        handlePause()
    }

    func handleDeviceChange(uid: String, name: String) {
        guard currentSession != nil, lastDeviceUID != uid else { return }
        // Device change during active playback triggers session close + new session
        // This will be handled naturally on the next NowPlaying update
    }

    // MARK: - Private

    private func handlePause() {
        guard currentSession != nil else { return }

        isPlaying = false
        if let sessionId = currentSession?.id {
            try? database.updateSessionActive(id: sessionId, isActive: false)
            currentSession?.isActive = false
        }

        // Start inactivity timer
        cancelPauseTimer()
        let timer = Timer(
            timeInterval: Constants.sessionInactivityTimeoutSeconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closeCurrentSession()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pauseTimer = timer
    }

    private func cancelPauseTimer() {
        pauseTimer?.invalidate()
        pauseTimer = nil
    }

    private func startNewSession(appBundleId: String, appName: String, device: AudioDevice) {
        let session = PlaybackSession(
            appBundleId: appBundleId,
            appName: appName,
            outputDeviceUID: device.uid,
            outputDeviceName: device.name,
            startedAt: Date(),
            isActive: true
        )

        do {
            let saved = try database.createSession(session)
            currentSession = saved
        } catch {
            debugLog("[SessionManager] Failed to create session: \(error)")
        }
    }

    private func closeCurrentSession() {
        finalizeCurrentTrack(elapsed: nil)

        guard let session = currentSession, let sessionId = session.id else {
            resetState()
            return
        }

        let duration = Date().timeIntervalSince(session.startedAt)

        if duration < Constants.minimumSessionDurationSeconds {
            // Discard very short sessions
            try? database.deleteSession(id: sessionId)
        } else {
            try? database.closeSession(id: sessionId, endedAt: Date())
        }

        resetState()
    }

    private func resetState() {
        currentSession = nil
        currentTrack = nil
        lastAppBundleId = nil
        lastDeviceUID = nil
        lastTrackTitle = nil
        lastTrackArtist = nil
        trackStartedAt = nil
        cancelPauseTimer()
    }

    private func startNewTrack(
        title: String?,
        artist: String?,
        album: String?,
        artworkData: Data?,
        duration: Double?,
        sourceURI: String? = nil
    ) {
        guard let sessionId = currentSession?.id else {
            debugLog("[SessionManager] startNewTrack: no session id, skipping")
            return
        }
        debugLog("[SessionManager] startNewTrack: sessionId=\(sessionId) title=\(title ?? "nil") artist=\(artist ?? "nil")")

        let processedArtwork = artworkData.flatMap { resizeArtwork($0) }

        let entry = TrackEntry(
            sessionId: sessionId,
            title: title,
            artist: artist,
            album: album,
            artworkData: processedArtwork,
            startedAt: Date(),
            durationSeconds: duration,
            sourceURI: sourceURI
        )

        do {
            let saved = try database.addTrackEntry(entry)
            currentTrack = saved
            trackStartedAt = Date()
        } catch {
            debugLog("[SessionManager] Failed to add track entry: \(error)")
        }
    }

    private func finalizeCurrentTrack(elapsed: Double?) {
        guard let track = currentTrack, let trackId = track.id else { return }

        let elapsedSeconds: Double
        if let elapsed {
            elapsedSeconds = elapsed
        } else if let started = trackStartedAt {
            elapsedSeconds = Date().timeIntervalSince(started)
        } else {
            return
        }

        try? database.updateTrackEntryElapsed(id: trackId, elapsedSeconds: elapsedSeconds)
    }

    private func resizeArtwork(_ data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }

        let pixelSize = Int(Constants.artworkThumbnailSize)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: pixelSize, height: pixelSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: Constants.artworkJPEGQuality])
    }
}
