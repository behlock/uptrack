import AppKit
import HotKey

@MainActor
final class HotkeyManager {
    var onHotkeyActivated: (() -> Void)?
    private var hotKey: HotKey?

    func start() {
        hotKey = HotKey(key: .tab, modifiers: [.option, .shift])
        hotKey?.keyDownHandler = { [weak self] in
            self?.onHotkeyActivated?()
        }
        debugLog("[HotkeyManager] Started — Option+Shift+Tab to activate bezel")
    }

    func stop() {
        hotKey = nil
    }
}
