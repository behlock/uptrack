import Foundation
import GRDB
import os

final class DatabaseManager: Sendable {
    private let dbQueue: DatabaseQueue

    /// On-disk database in Application Support (production).
    convenience init() throws {
        try FileManager.default.createDirectory(
            at: Constants.databaseDirectoryURL,
            withIntermediateDirectories: true
        )
        let dbQueue = try DatabaseQueue(
            path: Constants.databaseURL.path,
            configuration: Self.configuration()
        )
        // Enable WAL mode (must be outside a transaction)
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        try self.init(dbQueue: dbQueue)
    }

    /// In-memory database (tests).
    static func inMemory() throws -> DatabaseManager {
        try DatabaseManager(dbQueue: DatabaseQueue(configuration: configuration()))
    }

    private init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        var migrator = DatabaseMigrator()
        AppMigrations.registerMigrations(&migrator)
        try migrator.migrate(dbQueue)
    }

    private static func configuration() -> Configuration {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            #if DEBUG
                db.trace { Logger.database.debug("SQL: \($0)") }
            #endif
        }
        return config
    }

    // MARK: - Sessions

    @discardableResult
    func createSession(_ session: PlaybackSession) throws -> PlaybackSession {
        try dbQueue.write { db in
            let record = try session.inserted(db)
            Logger.database.debug("Created session id=\(record.id ?? -1)")
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

    // MARK: - Track Entries

    @discardableResult
    func addTrackEntry(_ entry: TrackEntry) throws -> TrackEntry {
        try dbQueue.write { db in
            try entry.inserted(db)
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

    func fetchTrackEntry(id: Int64) throws -> TrackEntry? {
        try dbQueue.read { db in
            try TrackEntry.fetchOne(db, id: id)
        }
    }

    // MARK: - Recent Tracks

    /// Async sequence that emits the most recent tracks immediately and then
    /// re-emits whenever the underlying tables change.
    func recentTracksSequence(limit: Int) -> AsyncValueObservation<[BezelTrackItem]> {
        ValueObservation
            .tracking { db in try Self.fetchRecentTracks(db, limit: limit) }
            .values(in: dbQueue)
    }

    private static func fetchRecentTracks(_ db: Database, limit: Int) throws -> [BezelTrackItem] {
        let rows = try Row.fetchAll(db, sql: """
        SELECT t.id, t.title, t.artist, t.album, t.artwork_data,
               t.duration_seconds, t.started_at, t.source_uri,
               s.app_name, s.app_bundle_id, s.output_device_name
        FROM track_entries t
        INNER JOIN playback_sessions s ON s.id = t.session_id
        ORDER BY t.started_at DESC
        LIMIT ?
        """, arguments: [limit])
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

    // MARK: - Maintenance

    func deleteAllSessions() throws {
        try dbQueue.write { db in
            _ = try db.execute(sql: "DELETE FROM track_entries")
            _ = try db.execute(sql: "DELETE FROM playback_sessions")
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
