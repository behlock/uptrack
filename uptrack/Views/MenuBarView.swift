import SwiftUI

/// Native-style menu contents. Only view types that `MenuBarExtra(..., style: .menu)`
/// understands: `Button`, `Text`, `Divider`, `Menu` (for submenus), and `ForEach` of
/// those. Everything else (ScrollView, HStack, custom button styles, backgrounds,
/// frames) is silently dropped by the .menu renderer.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updaterController: UpdaterController
    @State private var tracks: [BezelTrackItem] = []

    var body: some View {
        Group {
            if !appState.mediaRemoteAvailable {
                Text("⚠︎ mediaremote unavailable — tracking disabled")
            }
            if !appState.databaseAvailable {
                Text("⚠︎ database unavailable — history not saved")
            }

            if tracks.isEmpty {
                Text("no tracks yet")
            } else {
                ForEach(tracks) { track in
                    trackButton(track)
                }
            }

            Divider()

            if !tracks.isEmpty {
                Button("clear all") { performClearAll() }
            }
            Button("settings…") { showSettings() }
                .keyboardShortcut(",")
            Button("quit uptrack") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onAppear { loadTracks() }
        .onChange(of: appState.currentTrack?.id) { loadTracks() }
    }

    @ViewBuilder
    private func trackButton(_ track: BezelTrackItem) -> some View {
        let canPlay = isPlayable(track) && track.title != nil
        Button(menuLabel(for: track)) { playBezelTrack(track) }
            .disabled(!canPlay)
    }

    private func menuLabel(for track: BezelTrackItem) -> String {
        let title = track.title?.lowercased() ?? "unknown track"
        let suffix = sourceSuffix(for: track.appBundleId)
        if let artist = track.artist?.lowercased(), !artist.isEmpty {
            return "\(title) — \(artist)\(suffix)"
        }
        return "\(title)\(suffix)"
    }

    private func sourceSuffix(for bundleId: String) -> String {
        let lower = bundleId.lowercased()
        if lower.contains("spotify") { return "  · spotify" }
        if lower.contains("com.apple.music") || lower.contains("com.apple.itunes") {
            return "  · music"
        }
        return ""
    }

    private func isPlayable(_ track: BezelTrackItem) -> Bool {
        let lower = track.appBundleId.lowercased()
        return lower.contains("spotify") || lower.contains("com.apple.music")
    }

    private func loadTracks() {
        guard let db = appState.databaseManager else { tracks = []; return }
        Task.detached(priority: .userInitiated) {
            let loaded = (try? db.recentTrackEntriesWithContext(limit: Constants.recentTrackLimit)) ?? []
            await MainActor.run { self.tracks = loaded }
        }
    }

    private func performClearAll() {
        do {
            try appState.databaseManager?.deleteAllSessions()
        } catch {
            debugLog("[MenuBarView] Failed to clear all sessions: \(error)")
        }
        appState.sessionManager?.resetAfterClearAll()
        tracks = []
    }

    private func showSettings() {
        SettingsWindowController.show(
            onCheckForUpdates: { updaterController.checkForUpdates() },
            canCheckForUpdates: updaterController.canCheckForUpdates
        )
    }
}
