import os
import SwiftUI

/// Native-style menu contents. Only view types that `MenuBarExtra(..., style: .menu)`
/// understands: `Button`, `Text`, `Divider`, `Menu` (for submenus), and `ForEach` of
/// those. Everything else (ScrollView, HStack, custom button styles, backgrounds,
/// frames) is silently dropped by the .menu renderer.
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let tracks = appState.trackStore?.tracks ?? []

        if !appState.mediaRemoteAvailable {
            Text("⚠︎ mediaremote unavailable — tracking via player notifications only")
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

    @ViewBuilder
    private func trackButton(_ track: BezelTrackItem) -> some View {
        let canPlay = track.source.isPlayable && track.title != nil
        let title = trackTitleText(track)
        Button(action: { PlaybackLauncher.play(track) }) {
            switch track.source {
            case .spotify:
                Text("\(title)  ·  \(Image("SpotifyIcon")) spotify")
            case .appleMusic:
                Text("\(title)  ·  \u{f8ff} music")
            case .other:
                Text(title)
            }
        }
        .disabled(!canPlay)
    }

    private func trackTitleText(_ track: BezelTrackItem) -> String {
        let title = track.title?.lowercased() ?? "unknown track"
        if let artist = track.artist?.lowercased(), !artist.isEmpty {
            return "\(title) — \(artist)"
        }
        return title
    }

    private func performClearAll() {
        do {
            try appState.databaseManager?.deleteAllSessions()
        } catch {
            Logger.app.debug("Failed to clear all sessions: \(error)")
        }
        appState.sessionManager?.resetAfterClearAll()
    }

    private func showSettings() {
        openSettings()
        // LSUIElement apps aren't active when their menu is clicked; activation is
        // needed so the Settings window comes to the front.
        NSApp.activate()
    }
}
