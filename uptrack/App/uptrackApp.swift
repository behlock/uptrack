import SwiftUI

@main
struct uptrackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var updaterController = UpdaterController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.appState)
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

/// Owns `AppState` for the whole process lifetime so `applicationWillTerminate`
/// can always shut it down. (Wiring it from the menu's `.onAppear` only worked
/// once the user had opened the menu at least once.)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationWillTerminate(_ notification: Notification) {
        appState.shutdown()
    }
}
