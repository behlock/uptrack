import SwiftUI

struct BezelContentView: View {
    @ObservedObject var controller: BezelController

    var body: some View {
        Group {
            if let item = controller.currentItem {
                trackView(item)
            } else {
                Text("no tracks")
                    .font(uptrackTheme.Fonts.body(12))
                    .foregroundStyle(uptrackTheme.Colors.textSecondary)
            }
        }
        .frame(
            width: uptrackTheme.Dimensions.bezelWidth,
            height: uptrackTheme.Dimensions.bezelHeight
        )
        .glassEffect(
            .regular,
            in: .rect(cornerRadius: uptrackTheme.Dimensions.bezelCornerRadius)
        )
        .clipShape(.rect(cornerRadius: uptrackTheme.Dimensions.bezelCornerRadius))
        .animation(.easeInOut(duration: 0.15), value: controller.currentIndex)
    }

    @ViewBuilder
    private func trackView(_ item: BezelTrackItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Position indicator
            HStack {
                Spacer()
                Text("\(controller.currentIndex + 1) / \(controller.totalCount)")
                    .font(uptrackTheme.Fonts.mono(10))
                    .foregroundStyle(uptrackTheme.Colors.textTertiary)
            }

            HStack(spacing: 12) {
                // Artwork (only if available)
                if let data = item.artworkData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: uptrackTheme.Dimensions.bezelArtwork,
                            height: uptrackTheme.Dimensions.bezelArtwork
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Track info
                VStack(alignment: .leading, spacing: 3) {
                    Text((item.title ?? "unknown track").lowercased())
                        .font(uptrackTheme.Fonts.body(14))
                        .foregroundStyle(uptrackTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Text((item.artist ?? "unknown artist").lowercased())
                        .font(uptrackTheme.Fonts.body(12))
                        .foregroundStyle(uptrackTheme.Colors.textSecondary)
                        .lineLimit(1)

                    AppNameLabel(appName: item.appName, appBundleId: item.appBundleId, fontSize: 10)
                        .lineLimit(1)

                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(relativeTime(item.startedAt))
                            .font(uptrackTheme.Fonts.mono(10))
                            .foregroundStyle(uptrackTheme.Colors.textTertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            // Hint
            Text("tab / ↑↓ browse · ⏎ play · release to close")
                .font(uptrackTheme.Fonts.mono(9))
                .foregroundStyle(uptrackTheme.Colors.textTertiary)
        }
        .padding(uptrackTheme.Spacing.contentPadding)
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
