import Foundation

/// The media player a track came from. Single source of truth for
/// bundle-id detection — replaces scattered `contains("spotify")` checks.
enum MediaSource: Sendable {
    case spotify
    case appleMusic
    case other

    init(bundleId: String) {
        let lower = bundleId.lowercased()
        if lower.contains("spotify") {
            self = .spotify
        } else if lower.contains("com.apple.music") || lower.contains("com.apple.itunes") {
            self = .appleMusic
        } else {
            self = .other
        }
    }

    /// Whether uptrack knows how to resume playback in this app.
    var isPlayable: Bool {
        self != .other
    }
}

extension BezelTrackItem {
    var source: MediaSource {
        MediaSource(bundleId: appBundleId)
    }
}
