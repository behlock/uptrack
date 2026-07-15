import Foundation
import Testing
@testable import uptrack

struct DistributedMediaInfoTests {
    private func spotifyNotification(_ userInfo: [String: Any]) -> Notification {
        Notification(
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            userInfo: userInfo
        )
    }

    @Test func parsesSpotifyPayload() {
        let info = DistributedMediaInfo.parse(spotifyNotification([
            "Name": "Song",
            "Artist": "Artist",
            "Album": "Album",
            "Player State": "Playing",
            "Duration": 215_000,
            "Playback Position": 12.5,
            "Track ID": "spotify:track:abc123",
        ]))

        #expect(info.bundleId == "com.spotify.client")
        #expect(info.appName == "Spotify")
        #expect(info.title == "Song")
        #expect(info.artist == "Artist")
        #expect(info.album == "Album")
        #expect(info.isPlaying)
        #expect(info.durationSeconds == 215.0)
        #expect(info.elapsedSeconds == 12.5)
        #expect(info.trackURI == "spotify:track:abc123")
    }

    @Test func parsesAppleMusicPayload() {
        let info = DistributedMediaInfo.parse(Notification(
            name: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            userInfo: [
                "Name": "Song",
                "Player State": "Paused",
                "Total Time": 180_000.0,
                "Player Position": 3.0,
            ]
        ))

        #expect(info.bundleId == "com.apple.Music")
        #expect(info.appName == "Music")
        #expect(!info.isPlaying)
        #expect(info.durationSeconds == 180.0)
        #expect(info.elapsedSeconds == 3.0)
        #expect(info.trackURI == nil)
    }

    @Test func unknownNotificationFallsBack() {
        let info = DistributedMediaInfo.parse(Notification(
            name: Notification.Name("com.example.player.state"),
            object: nil,
            userInfo: nil
        ))

        #expect(info.bundleId == "unknown")
        #expect(info.appName == "Unknown App")
        #expect(!info.isPlaying)
        #expect(info.title == nil)
    }
}
