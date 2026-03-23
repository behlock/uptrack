import Foundation
import GRDB

enum AppMigrations {
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { db in
            try db.create(table: "playback_sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("app_bundle_id", .text).notNull()
                t.column("app_name", .text).notNull()
                t.column("output_device_uid", .text)
                t.column("output_device_name", .text)
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("is_active", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "track_entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .integer).notNull()
                    .references("playback_sessions", onDelete: .cascade)
                t.column("title", .text)
                t.column("artist", .text)
                t.column("album", .text)
                t.column("artwork_data", .blob)
                t.column("started_at", .datetime).notNull()
                t.column("duration_seconds", .double)
                t.column("elapsed_seconds", .double)
            }

            try db.create(
                index: "idx_sessions_started_at",
                on: "playback_sessions",
                columns: ["started_at"]
            )
            try db.create(
                index: "idx_sessions_app",
                on: "playback_sessions",
                columns: ["app_bundle_id"]
            )
            try db.create(
                index: "idx_sessions_device",
                on: "playback_sessions",
                columns: ["output_device_uid"]
            )
            try db.create(
                index: "idx_tracks_session",
                on: "track_entries",
                columns: ["session_id"]
            )
            try db.create(
                index: "idx_tracks_started_at",
                on: "track_entries",
                columns: ["started_at"]
            )
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "track_entries") { t in
                t.add(column: "source_uri", .text)
            }
        }
    }
}
