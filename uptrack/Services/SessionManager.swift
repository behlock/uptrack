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
    /// True between scheduling a new track entry and its async persistence completing.
    /// Prevents duplicate track inserts while artwork is being resized off-main.
    private var pendingTrackStart = false

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

        if trackChanged || (currentTrack == nil && !pendingTrackStart) {
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

    /// Update the current track's source URI (e.g. Spotify track URI from distributed notifications).
    func patchCurrentTrackURI(_ uri: String) {
        guard let track = currentTrack, let trackId = track.id, track.sourceURI == nil else { return }
        currentTrack?.sourceURI = uri
        do {
            try database.updateTrackEntrySourceURI(id: trackId, sourceURI: uri)
        } catch {
            debugLog("[SessionManager] Failed to update track URI: \(error)")
        }
    }

    /// Patch in artwork fetched out-of-band (e.g. via AppleScript on macOS 26+ where
    /// MediaRemote no longer surfaces image data). Title/artist are passed by the caller
    /// so we can drop the patch if the user has skipped tracks while the fetch was
    /// in flight. If the new track is still being inserted (`pendingTrackStart`), we
    /// retry once after a short delay.
    func patchCurrentTrackArtwork(_ data: Data, title: String?, artist: String?) {
        if currentTrack == nil && pendingTrackStart
            && lastTrackTitle == title && lastTrackArtist == artist {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.patchCurrentTrackArtwork(data, title: title, artist: artist)
            }
            return
        }

        guard let track = currentTrack,
              let trackId = track.id,
              track.title == title,
              track.artist == artist,
              track.artworkData == nil else { return }

        let db = database
        Task.detached(priority: .utility) { [weak self] in
            guard let resized = SessionManager.resizeArtwork(data) else { return }
            do {
                try db.updateTrackEntryArtwork(id: trackId, artworkData: resized)
            } catch {
                debugLog("[SessionManager] Failed to update track artwork: \(error)")
                return
            }
            await MainActor.run {
                guard let self, self.currentTrack?.id == trackId else { return }
                self.currentTrack?.artworkData = resized
            }
        }
    }

    /// Reset state after all sessions have been deleted (e.g. "clear all").
    func resetAfterClearAll() {
        resetState()
        isPlaying = false
    }

    // MARK: - Private

    private func handlePause() {
        guard currentSession != nil else { return }

        isPlaying = false
        if let sessionId = currentSession?.id {
            do {
                try database.updateSessionActive(id: sessionId, isActive: false)
            } catch {
                debugLog("[SessionManager] Failed to update session active state: \(error)")
            }
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
            do {
                try database.deleteSession(id: sessionId)
            } catch {
                debugLog("[SessionManager] Failed to delete short session: \(error)")
            }
        } else {
            do {
                try database.closeSession(id: sessionId, endedAt: Date())
            } catch {
                debugLog("[SessionManager] Failed to close session: \(error)")
            }
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
        pendingTrackStart = false
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

        pendingTrackStart = true

        let startedAt = Date()
        let db = database
        let artworkTooLarge = (artworkData?.count ?? 0) > Constants.maxArtworkDataSize
        if artworkTooLarge, let artwork = artworkData {
            debugLog("[SessionManager] Artwork data too large (\(artwork.count) bytes), skipping")
        }
        let artworkForResize = artworkTooLarge ? nil : artworkData

        // Stay on the main actor for the outer Task (inherits @MainActor from enclosing
        // method); hop to a detached, utility-priority child Task only for the expensive
        // artwork resize + synchronous DB insert. This avoids Swift 6 "task-isolated self
        // in main-actor closure" diagnostics that strict concurrency reports when a
        // detached task captures self directly.
        Task { [weak self] in
            let saved = await Task.detached(priority: .utility) { () -> TrackEntry? in
                let processedArtwork = artworkForResize.flatMap { SessionManager.resizeArtwork($0) }
                let entry = TrackEntry(
                    sessionId: sessionId,
                    title: title,
                    artist: artist,
                    album: album,
                    artworkData: processedArtwork,
                    startedAt: startedAt,
                    durationSeconds: duration,
                    sourceURI: sourceURI
                )
                do {
                    return try db.addTrackEntry(entry)
                } catch {
                    debugLog("[SessionManager] Failed to add track entry: \(error)")
                    return nil
                }
            }.value

            guard let self else { return }
            // If state was reset (e.g. "clear all" or session closed) while the
            // resize/insert was in flight, drop the result.
            guard self.pendingTrackStart else { return }
            self.pendingTrackStart = false
            if let saved {
                self.currentTrack = saved
                self.trackStartedAt = startedAt
            }
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

        do {
            try database.updateTrackEntryElapsed(id: trackId, elapsedSeconds: elapsedSeconds)
        } catch {
            debugLog("[SessionManager] Failed to update track elapsed time: \(error)")
        }
    }

    nonisolated static func resizeArtwork(_ data: Data) -> Data? {
        guard let image = NSImage(data: data) else {
            debugLog("[SessionManager] resizeArtwork: NSImage(data:) returned nil")
            return nil
        }

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
