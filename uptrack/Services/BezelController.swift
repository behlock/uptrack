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
        let wasVisible = panel?.isVisible == true

        // Always refresh from DB so re-opens reflect tracks added since last show
        do {
            let tracks = try databaseManager.recentTrackEntriesWithContext(limit: Constants.recentTrackLimit)
            guard !tracks.isEmpty else {
                debugLog("[BezelController] No tracks to show")
                return
            }
            items = tracks
        } catch {
            debugLog("[BezelController] Failed to load tracks: \(error)")
            return
        }

        if wasVisible {
            // Already visible: treat repeat hotkey as "next track".
            // Tell the panel to swallow the poll's "newly pressed" immediate fire for
            // this same keystroke — Carbon just navigated, the poll must not navigate
            // again or every Option+Tab would advance by 2.
            navigateUp()
            panel?.suppressNextHotkeyFire()
            return
        }

        currentIndex = 0

        if panel == nil {
            createPanel()
        }

        panel?.centerOnCurrentScreen()
        panel?.orderFrontRegardless()
        panel?.makeKey()
        panel?.startKeyPolling()
        // First open: the hotkey key is still physically held. Without this the poll's
        // first "newly pressed" tick would fire and jump from index 0 to 1, making it
        // look like the first track is skipped.
        panel?.suppressNextHotkeyFire()
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
        guard let item = currentItem else { return }
        dismiss()
        playBezelTrack(item)
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
