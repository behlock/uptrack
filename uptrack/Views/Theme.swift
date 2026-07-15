import SwiftUI
import AppKit

// MARK: - Color Extensions

extension Color {
    init(light: String, dark: String) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark)
                : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        let parsed = trimmed.count == 6 && Scanner(string: trimmed).scanHexInt64(&rgb)
        if !parsed {
            assertionFailure("NSColor(hex:) expects a 6-character hex string, got: \(hex)")
            rgb = 0xFF00FF // magenta fallback in release builds — visible but non-crashing
        }
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Theme

enum uptrackTheme {
    enum Colors {
        static let textPrimary = Color(light: "#1A1A1A", dark: "#F0F0F0")
        static let textSecondary = Color(light: "#666666", dark: "#999999")
        static let textTertiary = Color(light: "#999999", dark: "#666666")
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
