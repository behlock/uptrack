import SwiftUI

// MARK: - Theme

enum uptrackTheme {
    enum Colors {
        static let textPrimary = Color(.textPrimary)
        static let textSecondary = Color(.textSecondary)
        static let textTertiary = Color(.textTertiary)
    }

    enum Fonts {
        static func body(_ size: CGFloat) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }

        static func mono(_ size: CGFloat) -> Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }
    }

    enum Spacing {
        static let contentPadding: CGFloat = 16
    }

    enum Dimensions {
        static let bezelWidth: CGFloat = 300
        static let bezelHeight: CGFloat = 180
        static let bezelArtwork: CGFloat = 64
        static let bezelCornerRadius: CGFloat = 12
    }
}

// MARK: - App Name Label

struct AppNameLabel: View {
    let appName: String
    let appBundleId: String
    var fontSize: CGFloat = 10

    var body: some View {
        switch MediaSource(bundleId: appBundleId) {
        case .spotify:
            HStack(spacing: 3) {
                Image("SpotifyIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: fontSize + 1)
                    .foregroundStyle(uptrackTheme.Colors.textTertiary)
                Text("spotify")
                    .font(uptrackTheme.Fonts.mono(fontSize))
                    .foregroundStyle(uptrackTheme.Colors.textTertiary)
            }
        case .appleMusic:
            Text("\u{f8ff} music")
                .font(uptrackTheme.Fonts.mono(fontSize))
                .foregroundStyle(uptrackTheme.Colors.textTertiary)
        case .other:
            Text(appName.lowercased())
                .font(uptrackTheme.Fonts.mono(fontSize))
                .foregroundStyle(uptrackTheme.Colors.textTertiary)
        }
    }
}
