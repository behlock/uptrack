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
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\n", with: "")
        .replacingOccurrences(of: "\u{00AC}", with: "") // ¬ AppleScript line continuation
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

    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
        appleScript.executeAndReturnError(&error)
    }
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
    let escaped = sanitizeForAppleScript(uri)
    let script = """
        tell application "Spotify"
            play track "\(escaped)"
        end tell
        """
    debugLog("[Spotify] Playing URI: \(uri)")
    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
        appleScript.executeAndReturnError(&error)
        if let error {
            debugLog("[Spotify] AppleScript error: \(error)")
        }
    }
}
