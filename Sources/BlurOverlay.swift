import AppKit

/// Full-screen, blurred, translucent scrim shown behind the unlock password
/// dialog. One panel is created per connected display so every screen gets
/// dimmed/blurred, matching the standard macOS lock-screen look.
///
/// Like `ToastWindow` and `PromptWindow`, these panels are purely visual:
/// `ignoresMouseEvents` is set via `FloatingPanel`, and they never take
/// keyboard focus. All real input handling stays inside `LockController`'s
/// `CGEventTap` callback.
final class BlurOverlay {

    private var panels: [FloatingPanel] = []

    var isVisible: Bool { !panels.isEmpty }

    /// Shows the blurred scrim on every screen. Safe to call again to adapt
    /// to a changed screen configuration.
    func show() {
        hide()

        for screen in NSScreen.screens {
            let panel = FloatingPanel(contentRect: screen.frame)
            panel.hasShadow = false

            let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
            effectView.autoresizingMask = [.width, .height]
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.state = .active

            // Medium-transparency dark tint on top of the blur, so the
            // background stays visible-but-dimmed rather than fully hidden.
            let tint = NSView(frame: effectView.bounds)
            tint.autoresizingMask = [.width, .height]
            tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
            effectView.addSubview(tint)

            panel.contentView = effectView
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panels.forEach { $0.animator().alphaValue = 1 }
        }
    }

    func hide() {
        let closing = panels
        panels = []
        guard !closing.isEmpty else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            closing.forEach { $0.orderOut(nil) }
        })
    }
}
