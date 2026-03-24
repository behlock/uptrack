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
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = PBTrackTheme.Dimensions.bezelCornerRadius
        visualEffect.layer?.masksToBounds = true

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
            width: PBTrackTheme.Dimensions.bezelWidth,
            height: PBTrackTheme.Dimensions.bezelHeight
        ))
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126, 124: // arrow up, arrow right
            onArrowUp?()
        case 125, 123: // arrow down, arrow left
            onArrowDown?()
        case 48: // tab
            if event.modifierFlags.contains(.shift) {
                onArrowUp?()
            } else {
                onArrowDown?()
            }
        case 36, 76: // return, numpad enter
            onPlay?()
        case 53: // escape
            onDismiss?()
        default:
            break
        }
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])
        // Dismiss when Option is released (the primary hotkey modifier)
        if !flags.contains(.option) {
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
