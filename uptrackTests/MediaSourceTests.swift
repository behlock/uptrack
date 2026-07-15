import Testing
@testable import uptrack

struct MediaSourceTests {
    @Test func detectsSpotify() {
        #expect(MediaSource(bundleId: "com.spotify.client") == .spotify)
        #expect(MediaSource(bundleId: "COM.SPOTIFY.CLIENT") == .spotify)
    }

    @Test func detectsAppleMusic() {
        #expect(MediaSource(bundleId: "com.apple.Music") == .appleMusic)
        #expect(MediaSource(bundleId: "com.apple.iTunes") == .appleMusic)
    }

    @Test func unknownAppsAreOther() {
        #expect(MediaSource(bundleId: "unknown") == .other)
        #expect(MediaSource(bundleId: "com.example.player") == .other)
        // Third-party apps with "music" in the name must not masquerade as Apple Music
        #expect(MediaSource(bundleId: "com.example.musicapp") == .other)
    }

    @Test func playability() {
        #expect(MediaSource.spotify.isPlayable)
        #expect(MediaSource.appleMusic.isPlayable)
        #expect(!MediaSource.other.isPlayable)
    }
}
