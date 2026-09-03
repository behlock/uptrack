import Foundation
import Testing
@testable import uptrack

@MainActor
struct BezelControllerTests {
    /// Builds an in-memory history with the given titles (oldest first) and a
    /// store that has observed them.
    private func makeStore(titles: [String]) async throws -> TrackHistoryStore {
        let db = try DatabaseManager.inMemory()
        let session = try db.createSession(PlaybackSession(
            appBundleId: "com.spotify.client",
            appName: "Spotify",
            outputDeviceUID: nil,
            outputDeviceName: nil,
            startedAt: Date(),
            isActive: true
        ))
        let sessionId = try #require(session.id)
        for (offset, title) in titles.enumerated() {
            try db.addTrackEntry(TrackEntry(
                sessionId: sessionId,
                title: title,
                artist: nil,
                album: nil,
                artworkData: nil,
                startedAt: Date().addingTimeInterval(Double(offset)),
                durationSeconds: nil,
                sourceURI: nil
            ))
        }

        let store = TrackHistoryStore(database: db)
        // The observation delivers asynchronously; wait (bounded) for the first emission.
        for _ in 0 ..< 500 where store.tracks.count != titles.count {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.tracks.count == titles.count)
        return store
    }

    @Test func storeListsNewestFirst() async throws {
        let store = try await makeStore(titles: ["A", "B", "C"])
        #expect(store.tracks.map(\.title) == ["C", "B", "A"])
    }

    @Test func showWithEmptyHistoryIsNoOp() async throws {
        let store = try await makeStore(titles: [])
        let controller = BezelController(trackStore: store)

        controller.show()

        #expect(controller.currentItem == nil)
        #expect(controller.totalCount == 0)
    }

    @Test func navigationWrapsAndDismissClears() async throws {
        let store = try await makeStore(titles: ["A", "B", "C"])
        let controller = BezelController(trackStore: store)

        controller.show()
        #expect(controller.totalCount == 3)
        #expect(controller.currentIndex == 0)
        #expect(controller.currentItem?.title == "C")

        controller.navigateDown()
        #expect(controller.currentIndex == 2)

        controller.navigateUp()
        controller.navigateUp()
        #expect(controller.currentIndex == 1)
        #expect(controller.currentItem?.title == "B")

        // Repeat hotkey while visible advances instead of resetting
        controller.show()
        #expect(controller.currentIndex == 2)

        controller.dismiss()
        #expect(controller.totalCount == 0)
        #expect(controller.currentItem == nil)
    }
}
