import SwiftUI

@main
struct uptrackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var updaterController = UpdaterController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .onAppear { appDelegate.appState = appState }
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .foregroundStyle(.primary)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(updaterController)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        appState?.shutdown()
    }
}
