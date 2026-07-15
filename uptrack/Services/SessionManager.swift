import AppKit
import Foundation
import Observation
import os

/// A now-playing snapshot from either metadata source (MediaRemote or
/// distributed notifications), normalized for session tracking.
struct NowPlayingUpdate: Sendable {
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
final class SessionManager {
    private(set) var currentSession: PlaybackSession?
    private(set) var currentTrack: TrackEntry?

    private let database: DatabaseManager
    private var pauseTimer: Timer?
    private var lastAppBundleId: String?
    private var lastDeviceUID: String?
    private var lastTrackTitle: String?
    private var lastTrackArtist: String?
    private var trackStartedAt: Date?
    /// In-flight track insert (artwork resize + DB write happen off-main).
    /// Non-nil while an insert is pending; awaited by the artwork patch so it
    /// lands on the freshly inserted row. Prevents duplicate inserts.
    private var trackInsertTask: Task<Void, Never>?
    /// Bumped whenever track state is torn down (reset / clear all). In-flight
    /// inserts compare against it and drop their result if stale.
    private var trackGeneration = 0

    init(database: DatabaseManager) {
        self.database = database

        // Close any sessions left active from a previous run
        do {
            try database.closeStaleActiveSessions()
        } catch {
            Logger.session.debug("Failed to close stale sessions: \(error)")
        }
    }

    func handleNowPlayingUpdate(_ update: NowPlayingUpdate, device: AudioDevice) {
        Logger.session.debug("handleNowPlayingUpdate: \(update.appName) | \(update.title ?? "nil") - \(update.artist ?? "nil") | playing: \(update.isPlaying) | device: \(device.name)")

        if !update.isPlaying {
            handlePause()
            return
        }

        // Cancel pause timer if resuming
        cancelPauseTimer()

        let appChanged = lastAppBundleId != nil && lastAppBundleId != update.appBundleId
        let deviceChanged = lastDeviceUID != nil && lastDeviceUID != device.uid

        if appChanged || deviceChanged {
            Logger.session.debug("App/device changed, closing session")
            closeCurrentSession()
        }

        if currentSession == nil {
            Logger.session.debug("Creating new session for \(update.appName)")
            startNewSession(
                appBundleId: update.appBundleId,
                appName: update.appName,
                device: device
            )
        }

        // Check if track changed
        let trackChanged = (update.title != lastTrackTitle || update.artist != lastTrackArtist)
            && (update.title != nil || update.artist != nil)

        if trackChanged || (currentTrack == nil && trackInsertTask == nil) {
            Logger.session.debug("Track changed: \(update.title ?? "nil") - \(update.artist ?? "nil"), saving...")
            finalizeCurrentTrack(elapsed: update.elapsedSeconds)
            startNewTrack(
                title: update.title,
                artist: update.artist,
                album: update.album,
                artworkData: update.artworkData,
                duration: update.durationSeconds,
                sourceURI: update.trackURI
            )
        }

        lastAppBundleId = update.appBundleId
        lastDeviceUID = device.uid
        lastTrackTitle = update.title
        lastTrackArtist = update.artist
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
            Logger.session.debug("Failed to update track URI: \(error)")
        }
    }

    /// Patch in artwork fetched out-of-band (e.g. via AppleScript on macOS 26+ where
    /// MediaRemote no longer surfaces image data). Title/artist are passed by the caller
    /// so we can drop the patch if the user has skipped tracks while the fetch was
    /// in flight. Awaits any in-flight track insert so the patch targets the new row.
    func patchCurrentTrackArtwork(_ data: Data, title: String?, artist: String?) {
        Task { [weak self] in
            await self?.trackInsertTask?.value

            guard let self,
                  let track = self.currentTrack,
                  let trackId = track.id,
                  track.title == title,
                  track.artist == artist,
                  track.artworkData == nil else { return }

            let db = self.database
            let resized: Data? = await Task.detached(priority: .utility) { () -> Data? in
                guard let resized = SessionManager.resizeArtwork(data) else { return nil }
                do {
                    try db.updateTrackEntryArtwork(id: trackId, artworkData: resized)
                } catch {
                    Logger.session.debug("Failed to update track artwork: \(error)")
                    return nil
                }
                return resized
            }.value

            guard let resized, self.currentTrack?.id == trackId else { return }
            self.currentTrack?.artworkData = resized
        }
    }

    /// Reset state after all sessions have been deleted (e.g. "clear all").
    func resetAfterClearAll() {
        resetState()
    }

    // MARK: - Private

    private func handlePause() {
        guard currentSession != nil else { return }

        if let sessionId = currentSession?.id {
            do {
                try database.updateSessionActive(id: sessionId, isActive: false)
            } catch {
                Logger.session.debug("Failed to update session active state: \(error)")
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
            Logger.session.debug("Failed to create session: \(error)")
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
                Logger.session.debug("Failed to delete short session: \(error)")
            }
        } else {
            do {
                try database.closeSession(id: sessionId, endedAt: Date())
            } catch {
                Logger.session.debug("Failed to close session: \(error)")
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
        trackInsertTask = nil
        trackGeneration += 1
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
            Logger.session.debug("startNewTrack: no session id, skipping")
            return
        }
        Logger.session.debug("startNewTrack: sessionId=\(sessionId) title=\(title ?? "nil") artist=\(artist ?? "nil")")

        let startedAt = Date()
        let db = database
        let artworkTooLarge = (artworkData?.count ?? 0) > Constants.maxArtworkDataSize
        if artworkTooLarge, let artwork = artworkData {
            Logger.session.debug("Artwork data too large (\(artwork.count) bytes), skipping")
        }
        let artworkForResize = artworkTooLarge ? nil : artworkData

        trackGeneration += 1
        let generation = trackGeneration

        // Stay on the main actor for the outer Task; hop to a detached, utility-priority
        // child Task only for the expensive artwork resize + synchronous DB insert.
        trackInsertTask = Task { [weak self] in
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
                    Logger.session.debug("Failed to add track entry: \(error)")
                    return nil
                }
            }.value

            guard let self else { return }
            // If state was reset or a newer track started while the resize/insert
            // was in flight, drop the result.
            guard self.trackGeneration == generation else { return }
            self.trackInsertTask = nil
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
            Logger.session.debug("Failed to update track elapsed time: \(error)")
        }
    }

    nonisolated static func resizeArtwork(_ data: Data) -> Data? {
        guard let image = NSImage(data: data) else {
            Logger.session.debug("resizeArtwork: NSImage(data:) returned nil")
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
