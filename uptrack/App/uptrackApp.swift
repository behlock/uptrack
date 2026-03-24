import SwiftUI

@main
struct uptrackApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updaterController = UpdaterController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(updaterController)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}
