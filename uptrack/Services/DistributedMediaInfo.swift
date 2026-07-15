import Foundation

/// Media metadata parsed from a player's distributed notification
/// (`com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo`).
struct DistributedMediaInfo: Sendable {
    let bundleId: String
    let appName: String
    let title: String?
    let artist: String?
    let album: String?
    let playerState: String?
    let durationSeconds: Double?
    let elapsedSeconds: Double?
    let trackURI: String?

    var isPlaying: Bool {
        playerState == "Playing"
    }

    static let knownApps: [String: (bundleId: String, name: String)] = [
        "com.spotify.client.PlaybackStateChanged": ("com.spotify.client", "Spotify"),
        "com.apple.Music.playerInfo": ("com.apple.Music", "Music"),
        "com.apple.iTunes.playerInfo": ("com.apple.Music", "Music"),
    ]

    static func parse(_ notification: Notification) -> DistributedMediaInfo {
        let userInfo = notification.userInfo ?? [:]
        let notifName = notification.name.rawValue
        let appInfo = knownApps[notifName]

        let title = truncateMetadata(userInfo["Name"] as? String)
        let artist = truncateMetadata(userInfo["Artist"] as? String)
        let album = truncateMetadata(userInfo["Album"] as? String)
        let playerState = userInfo["Player State"] as? String

        var durationSeconds: Double?
        if let d = userInfo["Duration"] as? Int {
            durationSeconds = Double(d) / 1000.0
        } else if let d = userInfo["Duration"] as? Double {
            durationSeconds = d / 1000.0
        } else if let d = userInfo["Total Time"] as? Int {
            durationSeconds = Double(d) / 1000.0
        } else if let d = userInfo["Total Time"] as? Double {
            durationSeconds = d / 1000.0
        }

        var elapsedSeconds: Double?
        if let p = userInfo["Playback Position"] as? Double {
            elapsedSeconds = p
        } else if let p = userInfo["Player Position"] as? Double {
            elapsedSeconds = p
        }

        let trackURI = truncateMetadata(userInfo["Track ID"] as? String)

        return DistributedMediaInfo(
            bundleId: appInfo?.bundleId ?? "unknown",
            appName: appInfo?.name ?? "Unknown App",
            title: title,
            artist: artist,
            album: album,
            playerState: playerState,
            durationSeconds: durationSeconds,
            elapsedSeconds: elapsedSeconds,
            trackURI: trackURI
        )
    }
}
