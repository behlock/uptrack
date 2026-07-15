import Testing
@testable import uptrack

struct PlaybackLauncherTests {
    @Test func validSpotifyURIs() {
        #expect(PlaybackLauncher.isValidSpotifyURI("spotify:track:4uLU6hMCjMI75M1A2tKUQC"))
        #expect(!PlaybackLauncher.isValidSpotifyURI("spotify:album:abc123"))
        #expect(!PlaybackLauncher.isValidSpotifyURI("spotify:track:"))
        #expect(!PlaybackLauncher.isValidSpotifyURI("spotify:track:abc\" -- injection"))
        #expect(!PlaybackLauncher.isValidSpotifyURI("https://open.spotify.com/track/abc"))
    }

    @Test func sanitizeEscapesQuotesAndBackslashes() {
        #expect(PlaybackLauncher.sanitizeForAppleScript(#"say "hi""#) == #"say \"hi\""#)
        #expect(PlaybackLauncher.sanitizeForAppleScript(#"a\b"#) == #"a\\b"#)
    }

    @Test func sanitizeStripsControlCharactersAndContinuation() {
        #expect(PlaybackLauncher.sanitizeForAppleScript("a\nb\tc\u{0}d") == "abcd")
        #expect(PlaybackLauncher.sanitizeForAppleScript("a\u{00AC}b") == "ab")
    }
}

struct MetadataTests {
    @Test func truncatesLongStrings() {
        let long = String(repeating: "x", count: 5000)
        #expect(truncateMetadata(long)?.count == Constants.maxMetadataStringLength)
        #expect(truncateMetadata("short") == "short")
        #expect(truncateMetadata(nil) == nil)
        #expect(truncateMetadata("") == "")
    }
}
