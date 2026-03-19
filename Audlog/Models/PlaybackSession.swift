import Foundation
import GRDB

struct PlaybackSession: Codable, Sendable, Identifiable, Equatable {
    var id: Int64?
    var appBundleId: String
    var appName: String
    var outputDeviceUID: String?
    var outputDeviceName: String?
    var startedAt: Date
    var endedAt: Date?
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case appBundleId = "app_bundle_id"
        case appName = "app_name"
        case outputDeviceUID = "output_device_uid"
        case outputDeviceName = "output_device_name"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case isActive = "is_active"
    }
}

extension PlaybackSession: FetchableRecord, PersistableRecord {
    static let databaseTableName = "playback_sessions"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension PlaybackSession {
    static let trackEntries = hasMany(TrackEntry.self)

    var trackEntries: QueryInterfaceRequest<TrackEntry> {
        request(for: PlaybackSession.trackEntries)
    }
}
