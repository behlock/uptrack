import AppKit
import SwiftUI

@MainActor
final class BezelController: ObservableObject {
    @Published var currentIndex: Int = 0
    @Published var items: [BezelTrackItem] = []

    private let databaseManager: DatabaseManager
    private var panel: BezelPanel?

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    var currentItem: BezelTrackItem? {
        guard !items.isEmpty, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var totalCount: Int { items.count }

    func show() {
        // If already visible, treat as "next track"
        if panel?.isVisible == true {
            navigateUp()
            return
        }

        do {
            let tracks = try databaseManager.recentTrackEntriesWithContext(limit: 50)
            guard !tracks.isEmpty else {
                debugLog("[BezelController] No tracks to show")
                return
            }
            items = tracks
            currentIndex = 0
        } catch {
            debugLog("[BezelController] Failed to load tracks: \(error)")
            return
        }

        if panel == nil {
            createPanel()
        }

        panel?.centerOnCurrentScreen()
        panel?.orderFrontRegardless()
        panel?.makeKey()
        panel?.startKeyPolling()
    }

    func dismiss() {
        panel?.stopKeyPolling()
        panel?.orderOut(nil)
        items = []
        currentIndex = 0
    }

    func navigateUp() {
        guard !items.isEmpty else { return }
        currentIndex = (currentIndex + 1) % items.count
    }

    func navigateDown() {
        guard !items.isEmpty else { return }
        currentIndex = (currentIndex - 1 + items.count) % items.count
    }

    func playCurrentTrack() {
        guard let item = currentItem, let title = item.title else { return }
        dismiss()

        let bundleId = item.appBundleId.lowercased()
        if bundleId.contains("spotify") {
            playInSpotify(item)
        } else {
            playTrackInAppleMusic(title: title)
        }
    }

    private func playInSpotify(_ item: BezelTrackItem) {
        if let uri = item.sourceURI {
            playTrackInSpotifyByURI(uri: uri)
        } else if let title = item.title {
            playTrackInSpotify(title: title, artist: item.artist)
        }
    }

    private func createPanel() {
        let contentView = BezelContentView(controller: self)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let bezelPanel = BezelPanel(contentView: hostingView)
        bezelPanel.onArrowUp = { [weak self] in self?.navigateUp() }
        bezelPanel.onArrowDown = { [weak self] in self?.navigateDown() }
        bezelPanel.onDismiss = { [weak self] in self?.dismiss() }
        bezelPanel.onPlay = { [weak self] in self?.playCurrentTrack() }

        panel = bezelPanel
    }
}
