import Foundation
import GRDB

struct TrackEntry: Codable, Sendable, Identifiable, Equatable {
    var id: Int64?
    var sessionId: Int64
    var title: String?
    var artist: String?
    var album: String?
    var artworkData: Data?
    var startedAt: Date
    var durationSeconds: Double?
    var elapsedSeconds: Double?
    var sourceURI: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case title
        case artist
        case album
        case artworkData = "artwork_data"
        case startedAt = "started_at"
        case durationSeconds = "duration_seconds"
        case elapsedSeconds = "elapsed_seconds"
        case sourceURI = "source_uri"
    }
}

extension TrackEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "track_entries"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension TrackEntry {
    static let session = belongsTo(PlaybackSession.self)
}
