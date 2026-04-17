import Foundation
import GRDB

final class DatabaseManager: Sendable {
    private let dbQueue: DatabaseQueue

    init() throws {
        let directoryURL = Constants.databaseDirectoryURL
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            #if DEBUG
            db.trace { debugLog("SQL: \($0)") }
            #endif
        }
        dbQueue = try DatabaseQueue(path: Constants.databaseURL.path, configuration: config)

        // Enable WAL mode (must be outside a transaction)
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        // Run migrations
        var migrator = DatabaseMigrator()
        AppMigrations.registerMigrations(&migrator)
        try migrator.migrate(dbQueue)
    }

    // MARK: - Sessions

    @discardableResult
    func createSession(_ session: PlaybackSession) throws -> PlaybackSession {
        try dbQueue.write { db in
            let record = try session.inserted(db)
            debugLog("[DatabaseManager] Created session id=\(record.id ?? -1)")
            return record
        }
    }

    func closeSession(id: Int64, endedAt: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE playback_sessions SET ended_at = ?, is_active = 0 WHERE id = ?",
                arguments: [endedAt, id]
            )
        }
    }

    func updateSessionActive(id: Int64, isActive: Bool) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE playback_sessions SET is_active = ? WHERE id = ?",
                arguments: [isActive, id]
            )
        }
    }

    func deleteSession(id: Int64) throws {
        try dbQueue.write { db in
            _ = try PlaybackSession.deleteOne(db, id: id)
        }
    }

    func recentSessions(limit: Int) throws -> [PlaybackSession] {
        try dbQueue.read { db in
            try PlaybackSession
                .order(Column("started_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func sessionsForDateRange(from startDate: Date, to endDate: Date) throws -> [PlaybackSession] {
        try dbQueue.read { db in
            try PlaybackSession
                .filter(Column("started_at") >= startDate && Column("started_at") <= endDate)
                .order(Column("started_at").desc)
                .fetchAll(db)
        }
    }

    func allSessions() throws -> [PlaybackSession] {
        try dbQueue.read { db in
            try PlaybackSession
                .order(Column("started_at").desc)
                .fetchAll(db)
        }
    }

    func searchSessions(query: String) throws -> [PlaybackSession] {
        let pattern = "%\(query)%"
        return try dbQueue.read { db in
            try PlaybackSession.fetchAll(db, sql: """
                SELECT DISTINCT s.* FROM playback_sessions s
                LEFT JOIN track_entries t ON t.session_id = s.id
                WHERE s.app_name LIKE ?
                   OR s.app_bundle_id LIKE ?
                   OR t.title LIKE ?
                   OR t.artist LIKE ?
                   OR t.album LIKE ?
                ORDER BY s.started_at DESC
                """, arguments: [pattern, pattern, pattern, pattern, pattern])
        }
    }

    // MARK: - Track Entries

    @discardableResult
    func addTrackEntry(_ entry: TrackEntry) throws -> TrackEntry {
        try dbQueue.write { db in
            let record = try entry.inserted(db)
            return record
        }
    }

    func trackEntries(forSessionId sessionId: Int64) throws -> [TrackEntry] {
        try dbQueue.read { db in
            try TrackEntry
                .filter(Column("session_id") == sessionId)
                .order(Column("started_at").asc)
                .fetchAll(db)
        }
    }

    func updateTrackEntryElapsed(id: Int64, elapsedSeconds: Double) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE track_entries SET elapsed_seconds = ? WHERE id = ?",
                arguments: [elapsedSeconds, id]
            )
        }
    }

    func updateTrackEntrySourceURI(id: Int64, sourceURI: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE track_entries SET source_uri = ? WHERE id = ?",
                arguments: [sourceURI, id]
            )
        }
    }

    func updateTrackEntryArtwork(id: Int64, artworkData: Data) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE track_entries SET artwork_data = ? WHERE id = ?",
                arguments: [artworkData, id]
            )
        }
    }

    // MARK: - Aggregates

    struct AppInfo: Sendable {
        let bundleId: String
        let name: String
        let count: Int
    }

    struct DeviceInfo: Sendable {
        let uid: String
        let name: String
        let count: Int
    }

    func distinctApps() throws -> [AppInfo] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT app_bundle_id, app_name, COUNT(*) as count
                FROM playback_sessions
                GROUP BY app_bundle_id
                ORDER BY count DESC
                """)
            return rows.map {
                AppInfo(
                    bundleId: $0["app_bundle_id"],
                    name: $0["app_name"],
                    count: $0["count"]
                )
            }
        }
    }

    func distinctDevices() throws -> [DeviceInfo] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT output_device_uid, output_device_name, COUNT(*) as count
                FROM playback_sessions
                WHERE output_device_uid IS NOT NULL
                GROUP BY output_device_uid
                ORDER BY count DESC
                """)
            return rows.map {
                DeviceInfo(
                    uid: $0["output_device_uid"],
                    name: $0["output_device_name"],
                    count: $0["count"]
                )
            }
        }
    }

    func trackCount(forSessionId sessionId: Int64) throws -> Int {
        try dbQueue.read { db in
            try TrackEntry.filter(Column("session_id") == sessionId).fetchCount(db)
        }
    }

    struct SessionWithTrackCount: Sendable {
        let session: PlaybackSession
        let trackCount: Int
    }

    func recentSessionsWithTrackCounts(limit: Int) throws -> [SessionWithTrackCount] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.*, COUNT(t.id) as track_count
                FROM playback_sessions s
                LEFT JOIN track_entries t ON t.session_id = s.id
                GROUP BY s.id
                ORDER BY s.started_at DESC
                LIMIT ?
                """, arguments: [limit])
            return try rows.map { row in
                let session = try PlaybackSession(row: row)
                let count: Int = row["track_count"]
                return SessionWithTrackCount(session: session, trackCount: count)
            }
        }
    }

    // MARK: - Bezel

    func allTrackEntriesWithContext() throws -> [BezelTrackItem] {
        try recentTrackEntriesWithContext(limit: nil)
    }

    func recentTrackEntriesWithContext(limit: Int) throws -> [BezelTrackItem] {
        try recentTrackEntriesWithContext(limit: Optional(limit))
    }

    private func recentTrackEntriesWithContext(limit: Int?) throws -> [BezelTrackItem] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.id, t.title, t.artist, t.album, t.artwork_data,
                       t.duration_seconds, t.started_at, t.source_uri,
                       s.app_name, s.app_bundle_id, s.output_device_name
                FROM track_entries t
                INNER JOIN playback_sessions s ON s.id = t.session_id
                ORDER BY t.started_at DESC
                \(limit != nil ? "LIMIT ?" : "")
                """, arguments: limit != nil ? [limit!] : [])
            return rows.map { row in
                BezelTrackItem(
                    id: row["id"],
                    title: row["title"],
                    artist: row["artist"],
                    album: row["album"],
                    artworkData: row["artwork_data"],
                    durationSeconds: row["duration_seconds"],
                    startedAt: row["started_at"],
                    appName: row["app_name"],
                    appBundleId: row["app_bundle_id"],
                    outputDeviceName: row["output_device_name"],
                    sourceURI: row["source_uri"]
                )
            }
        }
    }

    // MARK: - Maintenance

    func deleteAllSessions() throws {
        try dbQueue.write { db in
            _ = try db.execute(sql: "DELETE FROM track_entries")
            _ = try db.execute(sql: "DELETE FROM playback_sessions")
        }
    }

    func deleteSessionsOlderThan(_ date: Date) throws {
        try dbQueue.write { db in
            _ = try PlaybackSession.filter(Column("started_at") < date).deleteAll(db)
        }
    }

    func databaseSizeBytes() throws -> Int64 {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "PRAGMA page_count"),
                  let row2 = try Row.fetchOne(db, sql: "PRAGMA page_size") else {
                return 0
            }
            let pageCount: Int64 = row[0]
            let pageSize: Int64 = row2[0]
            return pageCount * pageSize
        }
    }

    /// Close any sessions that were left active from a previous run
    func closeStaleActiveSessions() throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE playback_sessions
                SET is_active = 0, ended_at = COALESCE(ended_at, ?)
                WHERE is_active = 1
                """,
                arguments: [Date()]
            )
        }
    }
}
