import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var tracks: [BezelTrackItem] = []

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
                TEDivider().padding(.vertical, 6)
            }

            // Scrollable session history
            sessionsSection

            TEDivider().padding(.vertical, 4)

            Button(action: { clearAll() }) {
                Text("clear all")
                    .font(PBTrackTheme.Fonts.body(12))
                    .foregroundStyle(PBTrackTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PBTrackTheme.Spacing.rowHorizontal)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HighlightButtonStyle())
            .pointerCursor()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("quit")
                    .font(PBTrackTheme.Fonts.body(12))
                    .foregroundStyle(PBTrackTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PBTrackTheme.Spacing.rowHorizontal)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HighlightButtonStyle())
            .pointerCursor()
        }
        .padding(.vertical, PBTrackTheme.Spacing.unit)
        .frame(width: 320)
        .background(VisualEffectBlur(material: .fullScreenUI, blendingMode: .behindWindow))
        .onAppear { loadTracks() }
        .onChange(of: appState.isPlaying) { loadTracks() }
    }

    private func loadTracks() {
        tracks = (try? appState.databaseManager?.recentTrackEntriesWithContext(limit: 200)) ?? []
    }

    private func clearAll() {
        try? appState.databaseManager?.deleteAllSessions()
        tracks = []
    }

    // MARK: - Sections

    @ViewBuilder
    private func warningBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PBTrackTheme.Colors.warning)
            Text(message)
                .font(PBTrackTheme.Fonts.mono(11))
                .foregroundStyle(PBTrackTheme.Colors.textSecondary)
        }
        .padding(.horizontal, PBTrackTheme.Spacing.rowHorizontal)
        .padding(.vertical, PBTrackTheme.Spacing.unit)

        TEDivider().padding(.vertical, 4)
    }

    @ViewBuilder
    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("now playing")
                .teLabelStyle()
                .padding(.horizontal, PBTrackTheme.Spacing.rowHorizontal)
                .padding(.bottom, 2)

            if let session = appState.currentSession {
                HStack(alignment: .center, spacing: 6) {
                    AppNameLabel(appName: session.appName, appBundleId: session.appBundleId, fontSize: 13)

                    liveIndicator
                }
                .padding(.horizontal, PBTrackTheme.Spacing.rowHorizontal)
            }

            if let track = appState.currentTrack {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = track.title {
                        Text(title.lowercased())
                            .font(PBTrackTheme.Fonts.body(13))
                            .foregroundStyle(PBTrackTheme.Colors.textPrimary)
                            .lineLimit(1)
                    }
                    if let artist = track.artist {
                        Text(artist.lowercased())
                            .font(PBTrackTheme.Fonts.body(12))
                            .foregroundStyle(PBTrackTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, PBTrackTheme.Spacing.rowHorizontal)
            }

            if let session = appState.currentSession {
                Text(TimeFormatting.formatListeningDuration(since: session.startedAt))
                    .font(PBTrackTheme.Fonts.mono(11))
                    .foregroundStyle(PBTrackTheme.Colors.textTertiary)
                    .padding(.horizontal, PBTrackTheme.Spacing.rowHorizontal)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var sessionsSection: some View {
        if tracks.isEmpty {
            Text("no tracks yet")
                .font(PBTrackTheme.Fonts.mono(11))
                .foregroundStyle(PBTrackTheme.Colors.textTertiary)
                .padding(.horizontal, PBTrackTheme.Spacing.rowHorizontal)
                .padding(.vertical, 4)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(tracks) { track in
                        trackRow(track)
                    }
                }
            }
            .frame(maxHeight: 400)
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
                            .font(PBTrackTheme.Fonts.body(12))
                            .foregroundStyle(PBTrackTheme.Colors.textPrimary)
                            .lineLimit(1)
                        if let artist = track.artist {
                            Text("—")
                                .font(PBTrackTheme.Fonts.body(11))
                                .foregroundStyle(PBTrackTheme.Colors.textTertiary)
                            Text(artist.lowercased())
                                .font(PBTrackTheme.Fonts.body(11))
                                .foregroundStyle(PBTrackTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                AppNameLabel(appName: track.appName, appBundleId: track.appBundleId, fontSize: 9)
            }
            .padding(.horizontal, PBTrackTheme.Spacing.rowHorizontal)
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
                .fill(PBTrackTheme.Colors.accent)
                .frame(width: 6, height: 6)
            Text("live")
                .font(PBTrackTheme.Fonts.mono(13))
                .foregroundStyle(PBTrackTheme.Colors.accent)
        }
    }

}
