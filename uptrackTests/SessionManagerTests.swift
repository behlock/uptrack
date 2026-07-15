import Foundation
import Testing
@testable import uptrack

@MainActor
struct SessionManagerTests {
    private let device = AudioDevice(uid: "device-1", name: "Speakers")

    private func update(
        title: String? = "Song A",
        artist: String? = "Artist",
        bundleId: String = "com.spotify.client",
        appName: String = "Spotify",
        isPlaying: Bool = true,
        trackURI: String? = nil
    ) -> NowPlayingUpdate {
        NowPlayingUpdate(
            appBundleId: bundleId,
            appName: appName,
            title: title,
            artist: artist,
            album: nil,
            artworkData: nil,
            durationSeconds: 200,
            elapsedSeconds: 0,
            isPlaying: isPlaying,
            trackURI: trackURI
        )
    }

    @Test func startsSessionAndTrackOnPlay() async throws {
        let db = try DatabaseManager.inMemory()
        let manager = SessionManager(database: db)

        manager.handleNowPlayingUpdate(update(), device: device)
        await manager.trackInsertTask?.value

        #expect(manager.currentSession != nil)
        #expect(manager.currentSession?.appName == "Spotify")
        #expect(manager.currentTrack?.title == "Song A")
    }

    @Test func trackChangeInsertsNewTrack() async throws {
        let db = try DatabaseManager.inMemory()
        let manager = SessionManager(database: db)

        manager.handleNowPlayingUpdate(update(title: "Song A"), device: device)
        await manager.trackInsertTask?.value
        let firstId = manager.currentTrack?.id

        manager.handleNowPlayingUpdate(update(title: "Song B"), device: device)
        await manager.trackInsertTask?.value

        #expect(manager.currentTrack?.title == "Song B")
        #expect(manager.currentTrack?.id != firstId)
        // Same session throughout
        #expect(manager.currentSession != nil)
    }

    @Test func duplicateUpdatesDoNotDuplicateTracks() async throws {
        let db = try DatabaseManager.inMemory()
        let manager = SessionManager(database: db)

        manager.handleNowPlayingUpdate(update(), device: device)
        manager.handleNowPlayingUpdate(update(), device: device)
        manager.handleNowPlayingUpdate(update(), device: device)
        await manager.trackInsertTask?.value

        var iterator = db.recentTracksSequence(limit: 10).makeAsyncIterator()
        let tracks = try #require(try await iterator.next())
        #expect(tracks.count == 1)
    }

    @Test func pauseMarksSessionInactive() async throws {
        let db = try DatabaseManager.inMemory()
        let manager = SessionManager(database: db)

        manager.handleNowPlayingUpdate(update(), device: device)
        await manager.trackInsertTask?.value

        manager.handleNowPlayingUpdate(update(isPlaying: false), device: device)

        #expect(manager.currentSession?.isActive == false)
        // Session stays open (inactivity timeout hasn't elapsed)
        #expect(manager.currentSession != nil)
    }

    @Test func appChangeStartsNewSession() async throws {
        let db = try DatabaseManager.inMemory()
        let manager = SessionManager(database: db)

        manager.handleNowPlayingUpdate(update(), device: device)
        await manager.trackInsertTask?.value
        let firstSessionId = manager.currentSession?.id

        manager.handleNowPlayingUpdate(
            update(title: "Other Song", bundleId: "com.apple.Music", appName: "Music"),
            device: device
        )
        await manager.trackInsertTask?.value

        #expect(manager.currentSession?.id != firstSessionId)
        #expect(manager.currentSession?.appName == "Music")
    }

    @Test func patchesTrackURI() async throws {
        let db = try DatabaseManager.inMemory()
        let manager = SessionManager(database: db)

        manager.handleNowPlayingUpdate(update(), device: device)
        await manager.trackInsertTask?.value

        manager.patchCurrentTrackURI("spotify:track:abc123")
        #expect(manager.currentTrack?.sourceURI == "spotify:track:abc123")

        // A second patch must not overwrite the first
        manager.patchCurrentTrackURI("spotify:track:other")
        #expect(manager.currentTrack?.sourceURI == "spotify:track:abc123")
    }

    @Test func clearAllResetsState() async throws {
        let db = try DatabaseManager.inMemory()
        let manager = SessionManager(database: db)

        manager.handleNowPlayingUpdate(update(), device: device)
        await manager.trackInsertTask?.value

        try db.deleteAllSessions()
        manager.resetAfterClearAll()

        #expect(manager.currentSession == nil)
        #expect(manager.currentTrack == nil)
    }
}
