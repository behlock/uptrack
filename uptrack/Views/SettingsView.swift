import SwiftUI
import AppKit
import KeyboardShortcuts
import ServiceManagement

struct SettingsView: View {
    let onCheckForUpdates: () -> Void
    let canCheckForUpdates: Bool

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("launch on login")
                    .font(uptrackTheme.Fonts.body(12))
                    .foregroundStyle(uptrackTheme.Colors.textSecondary)

                Spacer()

                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            HStack {
                Text("main hotkey")
                    .font(uptrackTheme.Fonts.body(12))
                    .foregroundStyle(uptrackTheme.Colors.textSecondary)

                Spacer()

                KeyboardShortcuts.Recorder("", name: .showBezel)
            }

            HStack {
                Text("updates")
                    .font(uptrackTheme.Fonts.body(12))
                    .foregroundStyle(uptrackTheme.Colors.textSecondary)

                Spacer()

                Button(action: onCheckForUpdates) {
                    Text("check for updates")
                        .font(uptrackTheme.Fonts.body(12))
                        .foregroundStyle(uptrackTheme.Colors.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(uptrackTheme.Colors.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(!canCheckForUpdates)
            }

        }
        .padding(24)
        .frame(width: 300)
    }
}

@MainActor
final class SettingsWindowController {
    private static var window: NSWindow?

    static func show(onCheckForUpdates: @escaping () -> Void, canCheckForUpdates: Bool) {
        let settingsView = SettingsView(
            onCheckForUpdates: onCheckForUpdates,
            canCheckForUpdates: canCheckForUpdates
        )

        if let existing = window, existing.isVisible {
            let hostingView = NSHostingView(rootView: settingsView)
            hostingView.setFrameSize(hostingView.fittingSize)
            existing.contentView = hostingView
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.title = "settings"
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = win
    }
}
