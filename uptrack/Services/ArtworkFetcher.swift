import AppKit
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

    /// The AppleScript round-trips are synchronous, so they run on detached tasks.
    private static func spotifyArtworkURL() async -> URL? {
        await Task.detached(priority: .userInitiated) { () -> URL? in
            let script = """
            tell application "Spotify"
                if it is running then
                    return artwork url of current track
                end if
            end tell
            """
            guard let descriptor = runScript(script, label: "Spotify"),
                  let urlString = descriptor.stringValue,
                  !urlString.isEmpty else { return nil }
            return URL(string: urlString)
        }.value
    }

    private static func appleMusicArtwork() async -> Data? {
        await Task.detached(priority: .userInitiated) { () -> Data? in
            let script = """
            tell application "Music"
                if it is running then
                    if exists current track then
                        return raw data of artwork 1 of current track
                    end if
                end if
            end tell
            """
            guard let descriptor = runScript(script, label: "Music") else { return nil }
            // `raw data` arrives as a typeData descriptor; fall back to coercion if
            // AppleScript wrapped it as `typePicture` instead.
            let bytes = descriptor.data
            if !bytes.isEmpty {
                return bytes
            }
            if let coerced = descriptor.coerce(toDescriptorType: typeData)?.data, !coerced.isEmpty {
                return coerced
            }
            return nil
        }.value
    }

    private static func runScript(_ source: String, label: String) -> NSAppleEventDescriptor? {
        guard let appleScript = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&error)
        if let error {
            Logger.artwork.debug("\(label) AppleScript error: \(error)")
            return nil
        }
        return descriptor
    }
}
