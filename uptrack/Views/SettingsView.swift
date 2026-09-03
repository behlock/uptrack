import KeyboardShortcuts
import os
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(UpdaterController.self) private var updater

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    /// The toggle drives `SMAppService` directly and then re-reads the real status,
    /// so the switch always reflects the system's state (including when registration
    /// fails or is awaiting approval) without an `onChange` feedback loop.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { setLaunchAtLogin($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("launch on login")
                    .font(uptrackTheme.Fonts.body(12))
                    .foregroundStyle(uptrackTheme.Colors.textSecondary)

                Spacer()

                Toggle("launch on login", isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
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

                Button("check for updates") { updater.checkForUpdates() }
                    .buttonStyle(.glass)
                    .disabled(!updater.canCheckForUpdates)
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            Logger.app.error("Launch at login \(enabled ? "register" : "unregister") failed: \(error)")
        }
        // macOS may require the user to approve the login item in System Settings.
        if enabled, service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        launchAtLogin = service.status == .enabled
    }
}
