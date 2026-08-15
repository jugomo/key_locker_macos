import AppKit

/// Floating unlock prompt shown after the user holds Cmd for 3 seconds.
///
/// This window never receives real keyboard focus. `LockController` decodes
/// key presses itself from the `CGEventTap` callback and calls
/// `setTypedLength(_:)` / `showError(_:)` to keep this view in sync with an
/// internal password buffer. That keeps every keystroke funneled through a
/// single, auditable choke point instead of relying on normal window focus
/// while a global event tap is swallowing input.
final class PromptWindow {

    private let panel: FloatingPanel
    private let titleLabel: NSTextField
    private let dotsLabel: NSTextField
    private let hintLabel: NSTextField

    init() {
        let width: CGFloat = 380
        let height: CGFloat = 140
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height))

        let background = RoundedBackgroundView(frame: panel.contentView!.bounds)
        background.autoresizingMask = [.width, .height]

        titleLabel = NSTextField(labelWithString: "Enter Password to Unlock")
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 16, y: height - 40, width: width - 32, height: 22)
        titleLabel.autoresizingMask = [.width, .minYMargin]

        dotsLabel = NSTextField(labelWithString: "")
        dotsLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        dotsLabel.textColor = .white
        dotsLabel.alignment = .center
        dotsLabel.frame = NSRect(x: 16, y: height - 78, width: width - 32, height: 28)
        dotsLabel.autoresizingMask = [.width, .minYMargin]

        hintLabel = NSTextField(labelWithString: "Type your password, then press Return  \u{2022}  Esc to cancel")
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        hintLabel.alignment = .center
        hintLabel.frame = NSRect(x: 16, y: 16, width: width - 32, height: 16)
        hintLabel.autoresizingMask = [.width]

        background.addSubview(titleLabel)
        background.addSubview(dotsLabel)
        background.addSubview(hintLabel)
        panel.contentView = background
        panel.alphaValue = 0
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        setTypedLength(0)
        hintLabel.stringValue = "Type your password, then press Return  \u{2022}  Esc to cancel"
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        if let screen = NSScreen.main {
            panel.positionCenter(on: screen)
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }

    /// Updates the masked dot indicator to reflect `length` typed characters.
    func setTypedLength(_ length: Int) {
        let capped = min(length, 24)
        dotsLabel.stringValue = String(repeating: "\u{2022}", count: capped)
    }

    /// Briefly shows an error message (e.g. "Incorrect password") and shakes
    /// the panel, then restores the normal hint text.
    func showError(_ message: String) {
        hintLabel.stringValue = message
        hintLabel.textColor = NSColor.systemRed
        shake()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self = self, self.panel.isVisible else { return }
            self.hintLabel.stringValue = "Type your password, then press Return  \u{2022}  Esc to cancel"
            self.hintLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        }
    }

    private func shake() {
        let originalFrame = panel.frame
        let amplitude: CGFloat = 10
        let offsets: [CGFloat] = [0, amplitude, -amplitude, amplitude * 0.6, -amplitude * 0.6, 0]
        let positions: [CGFloat] = offsets.map { offset -> CGFloat in
            originalFrame.midX + offset
        }

        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = positions
        animation.duration = 0.35
        animation.calculationMode = .cubic
        panel.contentView?.layer?.add(animation, forKey: "shake")
    }
}
