import AppKit

/// Small floating notification shown whenever input is blocked, e.g.
/// "Input is locked" or the countdown while the user holds Cmd to unlock.
///
/// The toast never takes focus or blocks clicks (`ignoresMouseEvents = true`)
/// -- it is purely a status indicator drawn on top of everything else.
final class ToastWindow {

    private let panel: FloatingPanel
    private let label: NSTextField
    private var hideWorkItem: DispatchWorkItem?

    init() {
        let width: CGFloat = 420
        let height: CGFloat = 56
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height))

        let background = RoundedBackgroundView(frame: panel.contentView!.bounds)
        background.autoresizingMask = [.width, .height]

        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.frame = NSRect(x: 16, y: 8, width: width - 32, height: height - 16)
        label.autoresizingMask = [.width, .height]

        background.addSubview(label)
        panel.contentView = background
        panel.alphaValue = 0
    }

    /// Shows `text` on the toast, resetting the auto-hide timer.
    /// Pass `autoHide: false` to keep it visible until `hide()` is called
    /// explicitly (used for the "keep holding Cmd" countdown).
    func show(_ text: String, autoHide: Bool = true, duration: TimeInterval = 1.6) {
        hideWorkItem?.cancel()
        label.stringValue = text

        if let screen = NSScreen.main {
            panel.positionBottomCenter(on: screen)
        }

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }

        if autoHide {
            let workItem = DispatchWorkItem { [weak self] in self?.hide() }
            hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
        }
    }

    func hide() {
        hideWorkItem?.cancel()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }
}
