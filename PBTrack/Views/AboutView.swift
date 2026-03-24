import SwiftUI
import AppKit

struct AboutView: View {
    let onCheckForUpdates: () -> Void
    let canCheckForUpdates: Bool

    var body: some View {
        VStack(spacing: 16) {
            if let appIcon = NSApplication.shared.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            VStack(spacing: 4) {
                Text("pbtrack")
                    .font(PBTrackTheme.Fonts.heading(16))
                    .foregroundStyle(PBTrackTheme.Colors.textPrimary)

                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("version \(version)")
                        .font(PBTrackTheme.Fonts.mono(11))
                        .foregroundStyle(PBTrackTheme.Colors.textTertiary)
                }
            }

            Button(action: onCheckForUpdates) {
                Text("check for updates")
                    .font(PBTrackTheme.Fonts.body(12))
                    .foregroundStyle(PBTrackTheme.Colors.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(PBTrackTheme.Colors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .disabled(!canCheckForUpdates)
        }
        .padding(24)
        .frame(width: 280)
    }
}

@MainActor
final class AboutWindowController {
    private static var window: NSWindow?

    static func show(onCheckForUpdates: @escaping () -> Void, canCheckForUpdates: Bool) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = AboutView(
            onCheckForUpdates: onCheckForUpdates,
            canCheckForUpdates: canCheckForUpdates
        )

        let hostingView = NSHostingView(rootView: aboutView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.title = "about"
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = win
    }
}
