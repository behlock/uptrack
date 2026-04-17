import AppKit
import Foundation

/// Out-of-band artwork retrieval for the distributed-notifications path.
///
/// On macOS 26+ the MediaRemote private framework no longer surfaces artwork to
/// third-party processes, so the distributed-notification fallback (which carries
/// title/artist/album but no image) leaves `artwork_data` empty in the DB. This
/// helper queries the source app directly via AppleScript and is intended to be
/// called from a background context — both the AppleScript round-trip and the
/// Spotify HTTP fetch are synchronous.
enum ArtworkFetcher {
    /// Fetch current-track artwork bytes for the given source app, dispatched on a
    /// background queue. `completion` is invoked once with `nil` if the app isn't
    /// supported, isn't running, or returned no artwork.
    static func fetch(bundleId: String, completion: @escaping @Sendable (Data?) -> Void) {
        let lower = bundleId.lowercased()
        DispatchQueue.global(qos: .userInitiated).async {
            if lower.contains("spotify") {
                completion(fetchSpotifyArtwork())
            } else if lower.contains("music") || lower.contains("itunes") {
                completion(fetchAppleMusicArtwork())
            } else {
                completion(nil)
            }
        }
    }

    private static func fetchSpotifyArtwork() -> Data? {
        let script = """
            tell application "Spotify"
                if it is running then
                    return artwork url of current track
                end if
            end tell
            """
        guard let descriptor = runScript(script, label: "Spotify") else { return nil }
        guard let urlString = descriptor.stringValue,
              !urlString.isEmpty,
              let url = URL(string: urlString) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            debugLog("[ArtworkFetcher] Spotify artwork URL fetch failed: \(error)")
            return nil
        }
    }

    private static func fetchAppleMusicArtwork() -> Data? {
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
        if !bytes.isEmpty { return bytes }
        if let coerced = descriptor.coerce(toDescriptorType: typeData)?.data, !coerced.isEmpty {
            return coerced
        }
        return nil
    }

    private static func runScript(_ source: String, label: String) -> NSAppleEventDescriptor? {
        guard let appleScript = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&error)
        if let error {
            debugLog("[ArtworkFetcher] \(label) AppleScript error: \(error)")
            return nil
        }
        return descriptor
    }
}
