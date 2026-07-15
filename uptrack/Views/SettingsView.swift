import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(UpdaterController.self) private var updater

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

                Button("check for updates") { updater.checkForUpdates() }
                    .buttonStyle(.glass)
                    .disabled(!updater.canCheckForUpdates)
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
}
