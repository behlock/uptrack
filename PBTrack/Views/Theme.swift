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

    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        assert(hex.count == 6, "NSColor(hex:) expects a 6-character hex string, got: \(hex)")
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        let success = scanner.scanHexInt64(&rgb)
        assert(success, "NSColor(hex:) failed to parse hex string: \(hex)")
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Theme

enum PBTrackTheme {
    enum Colors {
        static let background = Color(light: "#FAFAFA", dark: "#1A1A1A")
        static let surface = Color(light: "#FFFFFF", dark: "#242424")
        static let textPrimary = Color(light: "#1A1A1A", dark: "#F0F0F0")
        static let textSecondary = Color(light: "#666666", dark: "#999999")
        static let textTertiary = Color(light: "#999999", dark: "#666666")
        static let accent = Color(hex: "#FF6600")
        static let border = Color(light: "#E0E0E0", dark: "#333333")
        static let divider = Color(light: "#EBEBEB", dark: "#2A2A2A")
        static let warning = Color(light: "#CC5500", dark: "#FF8833")
    }

    enum Fonts {
        static func heading(_ size: CGFloat) -> Font {
            .system(size: size, weight: .semibold, design: .default)
        }

        static func body(_ size: CGFloat) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }

        static func mono(_ size: CGFloat) -> Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }

        static func label(_ size: CGFloat) -> Font {
            .system(size: size, weight: .medium, design: .default)
        }
    }

    enum Spacing {
        static let unit: CGFloat = 8
        static let contentPadding: CGFloat = 16
        static let sectionGap: CGFloat = 24
        static let rowVertical: CGFloat = 12
        static let rowHorizontal: CGFloat = 16
    }

    enum Dimensions {
        static let cornerRadius: CGFloat = 4
        static let badgeRadius: CGFloat = 2
        static let borderWidth: CGFloat = 1
        static let menuBarAppIcon: CGFloat = 24
        static let historyAppIcon: CGFloat = 28
        static let trackArtwork: CGFloat = 20
        static let bezelWidth: CGFloat = 300
        static let bezelHeight: CGFloat = 180
        static let bezelArtwork: CGFloat = 64
        static let bezelCornerRadius: CGFloat = 12
    }
}

// MARK: - Reusable Views

struct TEDivider: View {
    var body: some View {
        Rectangle()
            .fill(PBTrackTheme.Colors.divider)
            .frame(height: 1)
    }
}

// MARK: - App Name Label

struct AppNameLabel: View {
    let appName: String
    let appBundleId: String
    var fontSize: CGFloat = 10

    var body: some View {
        let lower = appName.lowercased()
        if lower.contains("spotify") {
            HStack(spacing: 3) {
                Image("SpotifyIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: fontSize + 1)
                    .foregroundStyle(PBTrackTheme.Colors.textTertiary)
                Text("spotify")
                    .font(PBTrackTheme.Fonts.mono(fontSize))
                    .foregroundStyle(PBTrackTheme.Colors.textTertiary)
            }
        } else if lower.contains("music") || lower.contains("itunes") {
            Text("\u{f8ff} music")
                .font(PBTrackTheme.Fonts.mono(fontSize))
                .foregroundStyle(PBTrackTheme.Colors.textTertiary)
        } else {
            Text(lower)
                .font(PBTrackTheme.Fonts.mono(fontSize))
                .foregroundStyle(PBTrackTheme.Colors.textTertiary)
        }
    }
}

// MARK: - Visual Effect

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Button Styles

struct HighlightButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered || configuration.isPressed
                          ? PBTrackTheme.Colors.textPrimary.opacity(0.1)
                          : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}

// MARK: - View Modifiers

extension View {
    func teLabelStyle() -> some View {
        self
            .font(PBTrackTheme.Fonts.mono(10))
            .foregroundStyle(PBTrackTheme.Colors.textTertiary)
            .textCase(.lowercase)
            .tracking(0.5)
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    func pointerCursor() -> some View {
        self.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
