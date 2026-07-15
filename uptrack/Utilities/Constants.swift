import Foundation

enum Constants {
    static let databaseDirectoryName = "uptrack"
    static let databaseFileName = "uptrack.db"

    static var databaseURL: URL {
        databaseDirectoryURL.appendingPathComponent(databaseFileName)
    }

    static var databaseDirectoryURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent(databaseDirectoryName)
    }

    /// Maximum number of recent track rows to load for the menu bar and bezel
    static let recentTrackLimit = 50

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

/// Truncate a metadata string to prevent storage of excessively long values
func truncateMetadata(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return value }
    if value.count <= Constants.maxMetadataStringLength { return value }
    return String(value.prefix(Constants.maxMetadataStringLength))
}

// MARK: - Debug logging

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

    func shutdown() {
        queue.sync {
            try? fileHandle?.close()
            fileHandle = nil
        }
    }
}

func debugLogShutdown() {
    DebugLogger.shared.shutdown()
}

func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    DebugLogger.shared.log(message, date: Date())
    #endif
}
