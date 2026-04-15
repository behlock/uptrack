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
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Visual effect backdrop
        let cornerRadius = uptrackTheme.Dimensions.bezelCornerRadius
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.maskImage = Self.roundedMaskImage(cornerRadius: cornerRadius)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        self.contentView = visualEffect
        setContentSize(NSSize(
            width: uptrackTheme.Dimensions.bezelWidth,
            height: uptrackTheme.Dimensions.bezelHeight
        ))
    }

    override var canBecomeKey: Bool { true }

    // Polling-based key-hold detection. We can't rely on keyDown alone:
    // when the user's global hotkey includes Tab or an arrow, the Carbon
    // hotkey handler consumes those keyDown events even while our panel
    // is key, so holding the key never reaches -keyDown:. Polling
    // CGEventSource.keyState lets us detect the physical hold state
    // regardless of who consumed the event.
    private var pollTimer: Timer?
    private var heldKey: UInt16?
    private var holdElapsed: TimeInterval = 0
    private var nextFireAt: TimeInterval = 0
    private let pollInterval: TimeInterval = 0.02
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
            self?.pollTick()
        }
    }

    func stopKeyPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        heldKey = nil
        holdElapsed = 0
        nextFireAt = 0
    }

    private func pollTick() {
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
            // newly pressed: fire once immediately, arm the initial delay
            heldKey = pressed
            holdElapsed = 0
            nextFireAt = initialRepeatDelay
            fire(forward: forward)
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

    private static func roundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let edgeLength = 2.0 * cornerRadius + 1.0
        let size = NSSize(width: edgeLength, height: edgeLength)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.black.set()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius, left: cornerRadius,
            bottom: cornerRadius, right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
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
