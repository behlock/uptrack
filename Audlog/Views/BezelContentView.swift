import SwiftUI

struct BezelContentView: View {
    @ObservedObject var controller: BezelController

    var body: some View {
        Group {
            if let item = controller.currentItem {
                trackView(item)
            } else {
                Text("no tracks")
                    .font(AudlogTheme.Fonts.body(12))
                    .foregroundStyle(AudlogTheme.Colors.textSecondary)
            }
        }
        .frame(
            width: AudlogTheme.Dimensions.bezelWidth,
            height: AudlogTheme.Dimensions.bezelHeight
        )
        .animation(.easeInOut(duration: 0.15), value: controller.currentIndex)
    }

    @ViewBuilder
    private func trackView(_ item: BezelTrackItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Position indicator
            HStack {
                Spacer()
                Text("\(controller.currentIndex + 1) / \(controller.totalCount)")
                    .font(AudlogTheme.Fonts.mono(10))
                    .foregroundStyle(AudlogTheme.Colors.textTertiary)
            }

            HStack(spacing: 12) {
                // Artwork (only if available)
                if let data = item.artworkData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: AudlogTheme.Dimensions.bezelArtwork,
                            height: AudlogTheme.Dimensions.bezelArtwork
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Track info
                VStack(alignment: .leading, spacing: 3) {
                    Text((item.title ?? "unknown track").lowercased())
                        .font(AudlogTheme.Fonts.body(14))
                        .foregroundStyle(AudlogTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Text((item.artist ?? "unknown artist").lowercased())
                        .font(AudlogTheme.Fonts.body(12))
                        .foregroundStyle(AudlogTheme.Colors.textSecondary)
                        .lineLimit(1)

                    AppNameLabel(appName: item.appName, appBundleId: item.appBundleId, fontSize: 10)
                        .lineLimit(1)

                    Text(relativeTime(item.startedAt))
                        .font(AudlogTheme.Fonts.mono(10))
                        .foregroundStyle(AudlogTheme.Colors.textTertiary)
                }
            }

            Spacer(minLength: 0)

            // Hint
            Text("tab / ↑↓ browse · ⏎ play · release to close")
                .font(AudlogTheme.Fonts.mono(9))
                .foregroundStyle(AudlogTheme.Colors.textTertiary)
        }
        .padding(AudlogTheme.Spacing.contentPadding)
        .contentTransition(.opacity)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}
