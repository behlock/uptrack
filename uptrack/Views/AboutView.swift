import SwiftUI
import AppKit

struct AboutView: View {
    let onCheckForUpdates: () -> Void
    let canCheckForUpdates: Bool

    var body: some View {
        VStack(spacing: 16) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            VStack(spacing: 4) {
                Text("uptrack")
                    .font(uptrackTheme.Fonts.heading(16))
                    .foregroundStyle(uptrackTheme.Colors.textPrimary)

                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("version \(version)")
                        .font(uptrackTheme.Fonts.mono(11))
                        .foregroundStyle(uptrackTheme.Colors.textTertiary)
                }
            }

            Button(action: onCheckForUpdates) {
                Text("check for updates")
                    .font(uptrackTheme.Fonts.body(12))
                    .foregroundStyle(uptrackTheme.Colors.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(uptrackTheme.Colors.border, lineWidth: 1)
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
            // Update the view with fresh state before bringing to front
            let aboutView = AboutView(
                onCheckForUpdates: onCheckForUpdates,
                canCheckForUpdates: canCheckForUpdates
            )
            let hostingView = NSHostingView(rootView: aboutView)
            hostingView.setFrameSize(hostingView.fittingSize)
            existing.contentView = hostingView
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
