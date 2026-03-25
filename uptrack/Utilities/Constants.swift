import AppKit
import Foundation

enum Constants {
    static let databaseDirectoryName = "uptrack"
    static let databaseFileName = "uptrack.db"

    static var databaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(databaseDirectoryName).appendingPathComponent(databaseFileName)
    }

    static var databaseDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(databaseDirectoryName)
    }

    /// Sessions shorter than this are discarded on close
    static let minimumSessionDurationSeconds: TimeInterval = 3.0

    /// How long a paused session stays open before being auto-closed
    static let sessionInactivityTimeoutSeconds: TimeInterval = 30 * 60 // 30 minutes

    /// Artwork thumbnail size (width and height in points)
    static let artworkThumbnailSize: CGFloat = 100.0

    /// JPEG compression quality for artwork thumbnails
    static let artworkJPEGQuality: CGFloat = 0.7

    /// Maximum length for metadata strings from external sources
    static let maxMetadataStringLength = 1000

    /// Maximum artwork data size before processing (5 MB)
    static let maxArtworkDataSize = 5 * 1024 * 1024

    /// Debug log file
    static var debugLogURL: URL {
        databaseDirectoryURL.appendingPathComponent("debug.log")
    }
}

private final class DebugLogger: @unchecked Sendable {
    static let shared = DebugLogger()
    private let queue = DispatchQueue(label: "com.uptrack.debugLog", qos: .utility)
    private let formatter = ISO8601DateFormatter()
    private var fileHandle: FileHandle?

    func log(_ message: String, date: Date) {
        queue.async { [self] in
            let line = "[\(formatter.string(from: date))] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if fileHandle == nil {
                let url = Constants.debugLogURL
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                fileHandle = try? FileHandle(forWritingTo: url)
                fileHandle?.seekToEndOfFile()
            }

            if let handle = fileHandle {
                handle.write(data)
            }
        }
    }
}

func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    DebugLogger.shared.log(message, date: Date())
    #endif
}

/// Sanitize a string for safe interpolation into an AppleScript string literal.
/// Strips characters that could escape or terminate an AppleScript string.
private func sanitizeForAppleScript(_ value: String) -> String {
    var sanitized = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\u{00AC}", with: "") // ¬ AppleScript line continuation
    // Strip all control characters (null bytes, tabs, newlines, carriage returns, etc.)
    sanitized.unicodeScalars.removeAll { CharacterSet.controlCharacters.contains($0) }
    return sanitized
}

/// Validate that a string is a well-formed Spotify track URI
func isValidSpotifyURI(_ uri: String) -> Bool {
    uri.range(of: #"^spotify:track:[A-Za-z0-9]+$"#, options: .regularExpression) != nil
}

/// Truncate a metadata string to prevent storage of excessively long values
func truncateMetadata(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return value }
    if value.count <= Constants.maxMetadataStringLength { return value }
    return String(value.prefix(Constants.maxMetadataStringLength))
}

/// Execute an AppleScript on a background queue to prevent main thread blocking
private func executeAppleScript(_ source: String) {
    DispatchQueue.global(qos: .userInitiated).async {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: source) {
            appleScript.executeAndReturnError(&error)
            if let error {
                debugLog("[AppleScript] Error: \(error)")
            }
        }
    }
}

/// Safely execute an AppleScript search in Apple Music
func playTrackInAppleMusic(title: String) {
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

/// Open a Spotify search via URL scheme
func playTrackInSpotify(title: String, artist: String?) {
    let query = [title, artist].compactMap { $0 }.joined(separator: " ")
    guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "spotify:search:\(encoded)") else { return }
    debugLog("[Spotify] Opening search: \(url)")
    NSWorkspace.shared.open(url)
}

/// Play a specific track in Spotify by URI via AppleScript
func playTrackInSpotifyByURI(uri: String) {
    guard isValidSpotifyURI(uri) else {
        debugLog("[Spotify] Rejected invalid URI: \(uri)")
        return
    }
    let escaped = sanitizeForAppleScript(uri)
    let script = """
        tell application "Spotify"
            play track "\(escaped)"
        end tell
        """
    debugLog("[Spotify] Playing URI: \(uri)")
    executeAppleScript(script)
}
