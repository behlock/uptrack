import Foundation
import os

/// Out-of-band artwork retrieval for the distributed-notifications path.
///
/// On macOS 26+ the MediaRemote private framework no longer surfaces artwork to
/// third-party processes, so the distributed-notification fallback (which carries
/// title/artist/album but no image) leaves `artwork_data` empty in the DB. This
/// helper queries the source app directly via AppleScript.
enum ArtworkFetcher {
    /// Fetch current-track artwork bytes for the given source app. Returns `nil`
    /// if the app isn't supported, isn't running, or returned no artwork.
    static func fetch(bundleId: String) async -> Data? {
        switch MediaSource(bundleId: bundleId) {
        case .spotify:
            guard let url = await spotifyArtworkURL() else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                return data
            } catch {
                Logger.artwork.debug("Spotify artwork URL fetch failed: \(error)")
                return nil
            }
        case .appleMusic:
            return await appleMusicArtwork()
        case .other:
            return nil
        }
    }

    private static func spotifyArtworkURL() async -> URL? {
        let script = """
        tell application "Spotify"
            if it is running then
                return artwork url of current track
            end if
        end tell
        """
        guard let urlString = await AppleScriptRunner.shared.string(script, label: "Spotify artwork"),
              let url = URL(string: urlString),
              url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    private static func appleMusicArtwork() async -> Data? {
        let script = """
        tell application "Music"
            if it is running then
                if exists current track then
                    return raw data of artwork 1 of current track
                end if
            end if
        end tell
        """
        return await AppleScriptRunner.shared.data(script, label: "Music artwork")
    }
}
