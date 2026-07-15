import os

/// Categorized loggers for the unified logging system.
/// View live output with: `log stream --predicate 'subsystem == "com.uptrack.app"' --level debug`
extension Logger {
    private static let subsystem = "com.uptrack.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let database = Logger(subsystem: subsystem, category: "database")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let nowPlaying = Logger(subsystem: subsystem, category: "nowPlaying")
    static let artwork = Logger(subsystem: subsystem, category: "artwork")
    static let bezel = Logger(subsystem: subsystem, category: "bezel")
    static let playback = Logger(subsystem: subsystem, category: "playback")
    static let mediaRemote = Logger(subsystem: subsystem, category: "mediaRemote")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
}
