import AppKit
import Foundation

enum Constants {
    static let databaseDirectoryName = "PBTrack"
    static let databaseFileName = "pbtrack.db"

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

    /// Debounce interval for NowPlaying info change notifications
    static let nowPlayingDebounceSeconds: TimeInterval = 0.5

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
    private let queue = DispatchQueue(label: "com.pbtrack.debugLog", qos: .utility)
    private let formatter = ISO8601DateFormatter()

    func log(_ message: String, date: Date) {
        queue.async { [self] in
            let line = "[\(formatter.string(from: date))] \(message)\n"
            let url = Constants.debugLogURL
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: url)
            }
        }
    }
}

func debugLog(_ message: String) {
    print(message)
    DebugLogger.shared.log(message, date: Date())
}

/// Safely execute an AppleScript search in Apple Music
func playTrackInAppleMusic(title: String) {
    let escaped = title
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")

    let script = """
        tell application "Music"
            set results to (search library playlist 1 for "\(escaped)")
            if results is not {} then
                play item 1 of results
            end if
        end tell
        """

    DispatchQueue.global(qos: .userInitiated).async {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }
}

/// Open a Spotify search via URL scheme
func playTrackInSpotify(title: String, artist: String?) {
    let query = [title, artist].compactMap { $0 }.joined(separator: " ")
    guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "spotify:search:\(encoded)") else { return }
    NSWorkspace.shared.open(url)
}
