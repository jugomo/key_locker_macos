import AppKit

/// Base class for the small floating windows (toast, unlock prompt) that must
/// stay visible above everything else on screen -- including a full-screen
/// app's own Space -- without ever taking keyboard focus or intercepting
/// mouse clicks.
///
/// Both `Toast` and `PromptOverlay` are purely informational: while the lock
/// is engaged, all real keyboard/mouse handling happens inside the
/// `CGEventTap` callback in `LockController`, not through normal AppKit
/// responder chain. These windows only render UI; they never become key.
class FloatingPanel: NSPanel {

    convenience init(contentRect: NSRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Centers the panel horizontally on `screen`, near the bottom.
    func positionBottomCenter(on screen: NSScreen, bottomMargin: CGFloat = 90) {
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.minY + bottomMargin
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Centers the panel both horizontally and vertically on `screen`.
    func positionCenter(on screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Rounded, translucent background used by both the toast and the prompt.
class RoundedBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor.black.withAlphaComponent(0.82).setFill()
        path.fill()
    }

    override var isFlipped: Bool { true }
}
