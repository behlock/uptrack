import AppKit
import KeyboardShortcuts

@MainActor
final class HotkeyManager {
    var onHotkeyActivated: (() -> Void)?

    func start() {
        KeyboardShortcuts.onKeyDown(for: .showBezel) { [weak self] in
            self?.onHotkeyActivated?()
        }
        debugLog("[HotkeyManager] Started — listening for showBezel shortcut")
    }

    func stop() {
        KeyboardShortcuts.disable(.showBezel)
    }
}
