import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updaterController: UpdaterController
    @State private var tracks: [BezelTrackItem] = []
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appState.mediaRemoteAvailable {
                warningBanner(
                    "mediaremote framework unavailable. playback tracking is disabled."
                )
            }

            if !appState.databaseAvailable {
                warningBanner(
                    "database failed to initialize. session history will not be saved."
                )
            }

            if appState.isPlaying {
                nowPlayingSection
            }

            // Scrollable session history
            sessionsSection

            TEDivider().padding(.vertical, 4)

            Button(action: {
                AboutWindowController.show(
                    onCheckForUpdates: { updaterController.checkForUpdates() },
                    canCheckForUpdates: updaterController.canCheckForUpdates
                )
            }) {
                Text("about")
                    .font(uptrackTheme.Fonts.body(12))
                    .foregroundStyle(uptrackTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, uptrackTheme.Spacing.rowHorizontal)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HighlightButtonStyle())
            .pointerCursor()

            Button(action: { SettingsWindowController.show() }) {
                Text("settings")
                    .font(uptrackTheme.Fonts.body(12))
                    .foregroundStyle(uptrackTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, uptrackTheme.Spacing.rowHorizontal)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HighlightButtonStyle())
            .pointerCursor()

            Button(action: { showClearConfirmation = true }) {
                Text("clear all")
                    .font(uptrackTheme.Fonts.body(12))
                    .foregroundStyle(uptrackTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, uptrackTheme.Spacing.rowHorizontal)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HighlightButtonStyle())
            .pointerCursor()

            TEDivider().padding(.vertical, 4)

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("quit")
                    .font(uptrackTheme.Fonts.body(12))
                    .foregroundStyle(uptrackTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, uptrackTheme.Spacing.rowHorizontal)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HighlightButtonStyle())
            .pointerCursor()
        }
        .padding(.vertical, uptrackTheme.Spacing.unit)
        .frame(width: 320)
        .background(VisualEffectBlur(material: .fullScreenUI, blendingMode: .behindWindow))
        .onAppear { loadTracks() }
        .onChange(of: appState.isPlaying) { loadTracks() }
        .alert("clear all history?", isPresented: $showClearConfirmation) {
            Button("clear all", role: .destructive) { performClearAll() }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("this will permanently delete all sessions and tracks.")
        }
    }

    private func loadTracks() {
        tracks = (try? appState.databaseManager?.recentTrackEntriesWithContext(limit: 50)) ?? []
    }

    private func performClearAll() {
        try? appState.databaseManager?.deleteAllSessions()
        appState.sessionManager?.resetAfterClearAll()
        tracks = []
    }

    // MARK: - Sections

    @ViewBuilder
    private func warningBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(uptrackTheme.Colors.warning)
            Text(message)
                .font(uptrackTheme.Fonts.mono(11))
                .foregroundStyle(uptrackTheme.Colors.textSecondary)
        }
        .padding(.horizontal, uptrackTheme.Spacing.rowHorizontal)
        .padding(.vertical, uptrackTheme.Spacing.unit)

        TEDivider().padding(.vertical, 4)
    }

    @ViewBuilder
    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("now playing")
                .teLabelStyle()
                .padding(.horizontal, uptrackTheme.Spacing.rowHorizontal)
                .padding(.bottom, 2)

            if let session = appState.currentSession {
                HStack(alignment: .center, spacing: 6) {
                    AppNameLabel(appName: session.appName, appBundleId: session.appBundleId, fontSize: 13)

                    liveIndicator
                }
                .padding(.horizontal, uptrackTheme.Spacing.rowHorizontal)
            }

            if let track = appState.currentTrack {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = track.title {
                        Text(title.lowercased())
                            .font(uptrackTheme.Fonts.body(13))
                            .foregroundStyle(uptrackTheme.Colors.textPrimary)
                            .lineLimit(1)
                    }
                    if let artist = track.artist {
                        Text(artist.lowercased())
                            .font(uptrackTheme.Fonts.body(12))
                            .foregroundStyle(uptrackTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, uptrackTheme.Spacing.rowHorizontal)
            }

            if let session = appState.currentSession {
                Text(TimeFormatting.formatListeningDuration(since: session.startedAt))
                    .font(uptrackTheme.Fonts.mono(11))
                    .foregroundStyle(uptrackTheme.Colors.textTertiary)
                    .padding(.horizontal, uptrackTheme.Spacing.rowHorizontal)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var sessionsSection: some View {
        if tracks.isEmpty {
            Text("no tracks yet")
                .font(uptrackTheme.Fonts.mono(11))
                .foregroundStyle(uptrackTheme.Colors.textTertiary)
                .padding(.horizontal, uptrackTheme.Spacing.rowHorizontal)
                .padding(.vertical, 4)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(tracks) { track in
                        trackRow(track)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    @ViewBuilder
    private func trackRow(_ track: BezelTrackItem) -> some View {
        let isAppleMusic = track.appBundleId.contains("com.apple.Music")
        let isSpotify = track.appBundleId.lowercased().contains("spotify")
        let canPlay = (isAppleMusic || isSpotify) && track.title != nil
        Button(action: { if canPlay { playTrack(track) } }) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(track.title?.lowercased() ?? "unknown track")
                            .font(uptrackTheme.Fonts.body(12))
                            .foregroundStyle(uptrackTheme.Colors.textPrimary)
                            .lineLimit(1)
                        if let artist = track.artist {
                            Text("—")
                                .font(uptrackTheme.Fonts.body(11))
                                .foregroundStyle(uptrackTheme.Colors.textTertiary)
                            Text(artist.lowercased())
                                .font(uptrackTheme.Fonts.body(11))
                                .foregroundStyle(uptrackTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                AppNameLabel(appName: track.appName, appBundleId: track.appBundleId, fontSize: 9)
            }
            .padding(.horizontal, uptrackTheme.Spacing.rowHorizontal)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightButtonStyle())
        .pointerCursor()
    }

    private func playTrack(_ track: BezelTrackItem) {
        guard let title = track.title else { return }
        if track.appBundleId.lowercased().contains("spotify") {
            playInSpotify(track)
        } else {
            debugLog("[MenuBarView] playInAppleMusic: \(title) — bundleId: \(track.appBundleId)")
            playTrackInAppleMusic(title: title)
        }
    }

    private func playInSpotify(_ track: BezelTrackItem) {
        if let uri = track.sourceURI {
            debugLog("[MenuBarView] playInSpotify via URI: \(uri)")
            playTrackInSpotifyByURI(uri: uri)
        } else if let title = track.title {
            debugLog("[MenuBarView] playInSpotify via search: \(title)")
            playTrackInSpotify(title: title, artist: track.artist)
        }
    }

    // MARK: - Helpers

    private var liveIndicator: some View {
        HStack(alignment: .center, spacing: 4) {
            Circle()
                .fill(uptrackTheme.Colors.accent)
                .frame(width: 6, height: 6)
            Text("live")
                .font(uptrackTheme.Fonts.mono(13))
                .foregroundStyle(uptrackTheme.Colors.accent)
        }
    }

}
