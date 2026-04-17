import AppKit
import SwiftUI

final class BezelPanel: NSPanel {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onPlay: (() -> Void)?

    init(contentView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: true
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // The SwiftUI content (BezelContentView) applies `.glassEffect` for the
        // Liquid Glass surface and rounded clip — no AppKit blur layer needed.
        self.contentView = contentView
        setContentSize(NSSize(
            width: uptrackTheme.Dimensions.bezelWidth,
            height: uptrackTheme.Dimensions.bezelHeight
        ))
    }

    override var canBecomeKey: Bool { true }

    deinit {
        pollTimer?.invalidate()
    }

    // Polling-based key-hold detection. We can't rely on keyDown alone:
    // when the user's global hotkey includes Tab or an arrow, the Carbon
    // hotkey handler consumes those keyDown events even while our panel
    // is key, so holding the key never reaches -keyDown:. Polling
    // CGEventSource.keyState lets us detect the physical hold state
    // regardless of who consumed the event.
    // nonisolated(unsafe) so the NSPanel nonisolated deinit can invalidate the timer.
    // In practice pollTimer is only mutated from AppKit main-thread callbacks (startKeyPolling
    // is called from BezelController, stopKeyPolling from main-thread events / dismiss).
    private nonisolated(unsafe) var pollTimer: Timer?
    private var heldKey: UInt16?
    private var holdElapsed: TimeInterval = 0
    private var nextFireAt: TimeInterval = 0
    // Set to true by BezelController after the global hotkey fires (Carbon has already
    // performed the navigation). The poll then suppresses its own "newly pressed"
    // immediate fire for the next keypress so we don't double-navigate. Repeat fires
    // (after initialRepeatDelay) are unaffected — holding still cycles at the normal
    // rate.
    private var suppressNextImmediateFire = false

    /// Modifiers that must remain pressed to keep the bezel visible. When all of these
    /// are no longer held, the poll dismisses the panel. Set by `BezelController` from
    /// the current global hotkey's modifiers (typically `.option`). Empty means the
    /// bezel won't auto-dismiss on modifier release — user must press Escape / Enter.
    ///
    /// This is the backstop for `flagsChanged`: a `.nonactivatingPanel` doesn't
    /// reliably receive AppKit modifier-change events (the frontmost app remains key),
    /// so modifier release from flagsChanged alone can miss. Polling `NSEvent.modifierFlags`
    /// catches it regardless of who owns key status.
    var requiredModifiers: NSEvent.ModifierFlags = [.option]
    // 30 Hz polling: still well under a human key-hold latency threshold (~50 ms) but
    // 33% fewer ticks/CGEventSource.keyState calls than the previous 50 Hz loop.
    private let pollInterval: TimeInterval = 0.033
    private let initialRepeatDelay: TimeInterval = 0.35
    private let repeatInterval: TimeInterval = 0.08

    // keyCode -> navigation direction. true = forward (onArrowUp), false = back.
    private static let navKeys: [UInt16: Bool] = [
        126: true,  // arrow up
        124: true,  // arrow right
        48: true,   // tab (treated as forward regardless of shift)
        125: false, // arrow down
        123: false, // arrow left
    ]

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // return, numpad enter
            onPlay?()
        case 53: // escape
            onDismiss?()
        default:
            break
        }
    }

    func startKeyPolling() {
        stopKeyPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop, but its closure is nonisolated from the
            // compiler's perspective. Hop explicitly to @MainActor to call pollTick().
            Task { @MainActor in self?.pollTick() }
        }
    }

    /// Called by `BezelController` when the global hotkey (or `show()`) has just
    /// performed a navigation. The next "newly pressed" detection in `pollTick`
    /// is treated as a continuation of that same keystroke and does not fire again.
    func suppressNextHotkeyFire() {
        suppressNextImmediateFire = true
    }

    func stopKeyPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        heldKey = nil
        holdElapsed = 0
        nextFireAt = 0
        suppressNextImmediateFire = false
    }

    private func pollTick() {
        // Modifier-release dismissal (see `requiredModifiers` doc). AppKit's
        // flagsChanged doesn't fire reliably while a non-activating panel is on
        // screen — the frontmost app stays key. Polling NSEvent.modifierFlags
        // catches release regardless.
        if !requiredModifiers.isEmpty {
            let current = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !current.isSuperset(of: requiredModifiers) {
                stopKeyPolling()
                onDismiss?()
                return
            }
        }

        let pressed = Self.navKeys.keys.first { keyCode in
            CGEventSource.keyState(.combinedSessionState, key: keyCode)
        }

        guard let pressed else {
            heldKey = nil
            holdElapsed = 0
            nextFireAt = 0
            return
        }

        let forward = Self.navKeys[pressed] ?? true

        if heldKey != pressed {
            // newly pressed: fire once immediately, arm the initial delay.
            // Exception: when the global hotkey just fired (Carbon already navigated),
            // we swallow this one keystroke so a single Option+Tab press advances by 1,
            // not 2.
            heldKey = pressed
            holdElapsed = 0
            nextFireAt = initialRepeatDelay
            if suppressNextImmediateFire {
                suppressNextImmediateFire = false
            } else {
                fire(forward: forward)
            }
            return
        }

        holdElapsed += pollInterval
        if holdElapsed >= nextFireAt {
            fire(forward: forward)
            nextFireAt = holdElapsed + repeatInterval
        }
    }

    private func fire(forward: Bool) {
        if forward { onArrowUp?() } else { onArrowDown?() }
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])
        // Dismiss when Option is released (the primary hotkey modifier)
        if !flags.contains(.option) {
            stopKeyPolling()
            onDismiss?()
        }
    }

    func centerOnCurrentScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
