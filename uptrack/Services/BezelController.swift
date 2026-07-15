import AppKit
import KeyboardShortcuts
import Observation
import os
import SwiftUI

@MainActor
@Observable
final class BezelController {
    private(set) var currentIndex: Int = 0
    private(set) var items: [BezelTrackItem] = []

    private let trackStore: TrackHistoryStore
    @ObservationIgnored private var panel: BezelPanel?

    init(trackStore: TrackHistoryStore) {
        self.trackStore = trackStore
    }

    var currentItem: BezelTrackItem? {
        guard !items.isEmpty, items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var totalCount: Int {
        items.count
    }

    func show() {
        let wasVisible = panel?.isVisible == true

        // Snapshot the store so the list is stable while the bezel is open,
        // even if new tracks arrive mid-browse.
        let tracks = trackStore.tracks
        guard !tracks.isEmpty else {
            Logger.bezel.debug("No tracks to show")
            return
        }
        items = tracks

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

        // Keep auto-dismiss in sync with the user's current hotkey. If the shortcut
        // has no modifiers the bezel won't auto-close on key release — user must
        // explicitly dismiss with Escape or Enter.
        panel?.requiredModifiers = KeyboardShortcuts.getShortcut(for: .showBezel)?.modifiers ?? []

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
        PlaybackLauncher.play(item)
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
