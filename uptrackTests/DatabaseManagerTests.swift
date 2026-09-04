import Foundation
import Testing
@testable import uptrack

struct DatabaseManagerTests {
    private func makeSession(app: String = "Spotify", bundleId: String = "com.spotify.client") -> PlaybackSession {
        PlaybackSession(
            appBundleId: bundleId,
            appName: app,
            outputDeviceUID: "uid",
            outputDeviceName: "MacBook Pro Speakers",
            startedAt: Date(),
            isActive: true
        )
    }

    @Test func insertsAndObservesTracks() async throws {
        let db = try DatabaseManager.inMemory()
        let session = try db.createSession(makeSession())
        let sessionId = try #require(session.id)

        try db.addTrackEntry(TrackEntry(
            sessionId: sessionId,
            title: "Song A",
            artist: "Artist",
            album: nil,
            artworkData: nil,
            startedAt: Date(),
            durationSeconds: 200,
            sourceURI: "spotify:track:abc"
        ))

        var iterator = db.recentTracksSequence(limit: 10).makeAsyncIterator()
        let tracks = try #require(try await iterator.next())
        #expect(tracks.count == 1)
        #expect(tracks.first?.title == "Song A")
        #expect(tracks.first?.appName == "Spotify")
        #expect(tracks.first?.sourceURI == "spotify:track:abc")
    }

    @Test func observationEmitsOnChange() async throws {
        let db = try DatabaseManager.inMemory()
        let session = try db.createSession(makeSession())
        let sessionId = try #require(session.id)

        var iterator = db.recentTracksSequence(limit: 10).makeAsyncIterator()
        let initial = try #require(try await iterator.next())
        #expect(initial.isEmpty)

        try db.addTrackEntry(TrackEntry(
            sessionId: sessionId,
            title: "Song B",
            artist: nil,
            album: nil,
            artworkData: nil,
            startedAt: Date(),
            durationSeconds: nil,
            sourceURI: nil
        ))

        let updated = try #require(try await iterator.next())
        #expect(updated.map(\.title) == ["Song B"])
    }

    @Test func deleteAllSessionsCascades() async throws {
        let db = try DatabaseManager.inMemory()
        let session = try db.createSession(makeSession())
        let sessionId = try #require(session.id)
        try db.addTrackEntry(TrackEntry(
            sessionId: sessionId,
            title: "Song",
            artist: nil, album: nil, artworkData: nil,
            startedAt: Date(), durationSeconds: nil, sourceURI: nil
        ))

        try db.deleteAllSessions()

        var iterator = db.recentTracksSequence(limit: 10).makeAsyncIterator()
        let tracks = try #require(try await iterator.next())
        #expect(tracks.isEmpty)
    }

    @Test func closesStaleActiveSessions() throws {
        let db = try DatabaseManager.inMemory()
        let session = try db.createSession(makeSession())
        #expect(session.isActive)

        try db.closeStaleActiveSessions()

        // Reopening detection: creating a fresh session still works and gets a new id
        let second = try db.createSession(makeSession())
        #expect(second.id != session.id)
    }

    @Test func trackUpdates() throws {
        let db = try DatabaseManager.inMemory()
        let session = try db.createSession(makeSession())
        let track = try db.addTrackEntry(TrackEntry(
            sessionId: #require(session.id),
            title: "Song",
            artist: nil, album: nil, artworkData: nil,
            startedAt: Date(), durationSeconds: nil, sourceURI: nil
        ))
        let trackId = try #require(track.id)

        try db.updateTrackEntryElapsed(id: trackId, elapsedSeconds: 42)
        try db.updateTrackEntrySourceURI(id: trackId, sourceURI: "spotify:track:xyz")
        try db.updateTrackEntryArtwork(id: trackId, artworkData: Data([0x01]))

        let updated = try #require(try db.fetchTrackEntry(id: trackId))
        #expect(updated.elapsedSeconds == 42)
        #expect(updated.sourceURI == "spotify:track:xyz")
        #expect(updated.artworkData == Data([0x01]))
        #expect(try db.fetchTrackEntry(id: trackId + 1) == nil)
    }
}
