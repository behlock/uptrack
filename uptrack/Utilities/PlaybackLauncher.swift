import AppKit
import Foundation
import os

/// Resumes a historical track in its source app, preferring URI-level
/// playback (exact track) over a title search.
enum PlaybackLauncher {
    static func play(_ item: BezelTrackItem) {
        // Same rule the menu uses to disable rows: only known players, and only
        // when there is a title to search for.
        guard item.source.isPlayable, let title = item.title else { return }
        switch item.source {
        case .spotify:
            if let uri = item.sourceURI {
                Logger.playback.debug("Spotify via URI: \(uri)")
                playInSpotify(uri: uri)
            } else {
                Logger.playback.debug("Spotify via search: \(title)")
                searchInSpotify(title: title, artist: item.artist)
            }
        case .appleMusic:
            Logger.playback.debug("Apple Music search: \(title)")
            searchInAppleMusic(title: title)
        case .other:
            break
        }
    }

    // MARK: - Apple Music

    private static func searchInAppleMusic(title: String) {
        let escaped = sanitizeForAppleScript(title)
        let script = """
        tell application "Music"
            set results to (search library playlist 1 for "\(escaped)")
            if results is not {} then
                play item 1 of results
            end if
        end tell
        """
        executeAppleScript(script)
    }

    // MARK: - Spotify

    /// Open a Spotify search via URL scheme
    private static func searchInSpotify(title: String, artist: String?) {
        let query = [title, artist].compactMap { $0 }.joined(separator: " ")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "spotify:search:\(encoded)") else { return }
        Logger.playback.debug("Opening search: \(url)")
        NSWorkspace.shared.open(url)
    }

    /// Play a specific track in Spotify by URI via AppleScript
    private static func playInSpotify(uri: String) {
        guard isValidSpotifyURI(uri) else {
            Logger.playback.debug("Rejected invalid URI: \(uri)")
            return
        }
        let escaped = sanitizeForAppleScript(uri)
        let script = """
        tell application "Spotify"
            play track "\(escaped)"
        end tell
        """
        Logger.playback.debug("Playing URI: \(uri)")
        executeAppleScript(script)
    }

    // MARK: - Helpers

    /// Validate that a string is a well-formed Spotify track URI
    static func isValidSpotifyURI(_ uri: String) -> Bool {
        uri.range(of: #"^spotify:track:[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }

    /// Sanitize a string for safe interpolation into an AppleScript string literal.
    /// Strips characters that could escape or terminate an AppleScript string.
    static func sanitizeForAppleScript(_ value: String) -> String {
        var sanitized = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\u{00AC}", with: "") // ¬ AppleScript line continuation
        // Strip all control characters (null bytes, tabs, newlines, carriage returns, etc.)
        sanitized.unicodeScalars.removeAll { CharacterSet.controlCharacters.contains($0) }
        return sanitized
    }

    /// Execute an AppleScript off the main actor so a slow or unresponsive
    /// target app never blocks the UI (same approach as `ArtworkFetcher`).
    private static func executeAppleScript(_ source: String) {
        Task.detached(priority: .userInitiated) {
            guard let appleScript = NSAppleScript(source: source) else { return }
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                Logger.playback.debug("Error: \(error)")
            }
        }
    }
}
