import SwiftUI

@main
struct uptrackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var updaterController = UpdaterController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(updaterController)
                .onAppear { appDelegate.appState = appState }
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        do {
            try appState?.databaseManager?.deleteAllSessions()
        } catch {
            debugLog("[AppDelegate] Failed to clear database on quit: \(error)")
        }
    }
}
