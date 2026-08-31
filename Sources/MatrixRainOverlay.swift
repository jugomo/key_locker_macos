import AppKit
import CoreText

/// Full-screen "Matrix code" rain animation, shown behind the lock (when
/// enabled in Settings) on every connected display, until the user starts
/// the unlock flow (holding Cmd), at which point `LockController` hides this
/// and falls back to the normal `BlurOverlay` + `PromptWindow` -- this class
/// only ever affects what's shown while idle-locked, never the unlock
/// mechanic itself.
///
/// Ported from a web (Canvas 2D) version of the same effect: a persistent
/// off-screen bitmap plays the role the retained `<canvas>` buffer played
/// there, faded a little every tick instead of cleared, so glyphs leave a
/// trailing streak as they fall.
private extension MatrixBackgroundMode {
    /// Alpha applied to the translucent blur backdrop; `nil` for the solid
    /// black mode, which paints no `NSVisualEffectView` at all.
    var blurAlpha: CGFloat? {
        switch self {
        case .black: return nil
        case .screenBlur: return 0.55
        case .screenBlurSolid: return 1.0
        }
    }
}

final class MatrixRainOverlay {

    private final class ScreenLayer {
        let panel: FloatingPanel
        let rainView: MatrixRainView

        init(screen: NSScreen, mode: MatrixBackgroundMode) {
            panel = FloatingPanel(contentRect: screen.frame)
            panel.hasShadow = false
            // One notch below the toast/prompt/blur panels (all
            // `.screenSaver`) so those always float above the rain, however
            // the ordering of show()/hide() calls happens to interleave.
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)

            let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))

            if let blurAlpha = mode.blurAlpha {
                let effectView = NSVisualEffectView(frame: container.bounds)
                effectView.autoresizingMask = [.width, .height]
                effectView.material = .hudWindow
                effectView.blendingMode = .behindWindow
                effectView.state = .active
                effectView.alphaValue = blurAlpha
                container.addSubview(effectView)
            }

            let rain = MatrixRainView(frame: container.bounds, mode: mode)
            rain.autoresizingMask = [.width, .height]
            container.addSubview(rain)

            panel.contentView = container
            panel.alphaValue = 0
            rainView = rain
        }
    }

    private var layers: [ScreenLayer] = []

    var isVisible: Bool { !layers.isEmpty }

    /// Shows the rain on every screen. Safe to call again (e.g. to switch
    /// `mode`) -- it tears down and rebuilds from scratch.
    func show(mode: MatrixBackgroundMode) {
        hide()

        for screen in NSScreen.screens {
            let layer = ScreenLayer(screen: screen, mode: mode)
            layer.panel.orderFrontRegardless()
            layer.rainView.start()
            layers.append(layer)
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            layers.forEach { $0.panel.animator().alphaValue = 1 }
        }
    }

    func hide() {
        let closing = layers
        layers = []
        guard !closing.isEmpty else { return }

        closing.forEach { $0.rainView.stop() }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            closing.forEach { $0.panel.animator().alphaValue = 0 }
        }, completionHandler: {
            closing.forEach { $0.panel.orderOut(nil) }
        })
    }
}

/// Draws the falling-glyphs animation into a persistent off-screen bitmap on
/// a timer, then blits that bitmap as the view's layer contents each tick.
private final class MatrixRainView: NSView {

    private static let glyphs = Array(
        "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    )
    private static let fontSize: CGFloat = 22
    private static let frameInterval: TimeInterval = 1.0 / 30.0

    // Most columns fall at `normalDropSpeed`; a rare few are dealt
    // `fastDropSpeed` instead (re-rolled each time a column resets to the
    // top), so every so often a streak rips down the screen noticeably
    // faster than the rest. `fastDropSpeed` is a fixed multiple of the
    // normal speed, not itself randomized -- every "fast" column falls at
    // exactly the same speed.
    private static let normalDropSpeed: CGFloat = 0.9
    private static let fastDropSpeed: CGFloat = normalDropSpeed * 1.7
    private static let fastDropChance: Double = 0.05

    private let mode: MatrixBackgroundMode
    private let font = NSFont(name: "Menlo", size: MatrixRainView.fontSize)
        ?? NSFont.monospacedSystemFont(ofSize: MatrixRainView.fontSize, weight: .regular)

    private var timer: Timer?
    private var bitmapContext: CGContext?
    private var drops: [CGFloat] = []
    private var dropSpeeds: [CGFloat] = []

    init(frame: NSRect, mode: MatrixBackgroundMode) {
        self.mode = mode
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func start() {
        stop()
        setUpBitmap(forceReset: true)
        let t = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if timer != nil {
            setUpBitmap(forceReset: true)
        }
    }

    private func setUpBitmap(forceReset: Bool) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelWidth = max(1, Int(bounds.width * scale))
        let pixelHeight = max(1, Int(bounds.height * scale))
        guard forceReset || bitmapContext == nil else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // Work in point coordinates with a top-left origin, so row 0 lines
        // up with the top of the screen and the falling-drop math below
        // (drops grow downward from y = 0) reads naturally.
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        if mode == .black {
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
        }

        bitmapContext = ctx
        drops = Self.freshDrops(columns: columnCount())
        dropSpeeds = Self.freshDropSpeeds(columns: drops.count)
    }

    private func columnCount() -> Int {
        max(1, Int(bounds.width / Self.fontSize))
    }

    private static func freshDrops(columns: Int) -> [CGFloat] {
        (0..<columns).map { _ in CGFloat.random(in: -40...0) }
    }

    private static func freshDropSpeeds(columns: Int) -> [CGFloat] {
        (0..<columns).map { _ in randomDropSpeed() }
    }

    private static func randomDropSpeed() -> CGFloat {
        Double.random(in: 0...1) < fastDropChance ? fastDropSpeed : normalDropSpeed
    }

    private func tick() {
        guard let ctx = bitmapContext, bounds.width > 0, bounds.height > 0 else { return }

        let columns = columnCount()
        if drops.count != columns {
            drops = Self.freshDrops(columns: columns)
            dropSpeeds = Self.freshDropSpeeds(columns: columns)
        }

        // Fade the previous frame instead of clearing it, so glyphs leave a
        // trailing streak -- the same trick the web canvas version relies on
        // by painting a low-alpha rect every frame instead of clearRect().
        if mode == .black {
            ctx.setBlendMode(.normal)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.06).cgColor)
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
        } else {
            // No opaque background to fade *into* here -- the blur shows
            // through instead -- so fade the glyphs' own alpha toward zero.
            ctx.setBlendMode(.destinationOut)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.08).cgColor)
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
            ctx.setBlendMode(.normal)
        }

        for i in 0..<columns {
            let x = CGFloat(i) * Self.fontSize
            let y = drops[i] * Self.fontSize

            let isHead = drops[i] > 1 && Double.random(in: 0...1) > 0.95
            // Movie effect: the bright head glyph occasionally solidifies
            // into a filled block instead of a character, softened with a
            // little transparency so it doesn't read as a hard, over-crisp
            // square against the rest of the stream.
            let isBlock = isHead && Double.random(in: 0...1) < 0.08
            let glyph = isBlock ? "█" : String(Self.glyphs.randomElement()!)
            let color: NSColor = isHead
                ? NSColor.white.withAlphaComponent(isBlock ? 0.6 : 1)
                : NSColor(
                    calibratedHue: 0.33,
                    saturation: 1,
                    brightness: CGFloat.random(in: 0.35...0.75),
                    alpha: mode == .black ? 1 : 0.9
                )

            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color.cgColor]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: attrs))
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, ctx)

            if y > bounds.height, Double.random(in: 0...1) > 0.975 {
                drops[i] = 0
                // Re-roll the speed each time a column starts a fresh run,
                // so a given column doesn't stay fast (or normal) forever.
                dropSpeeds[i] = Self.randomDropSpeed()
            }
            drops[i] += dropSpeeds[i]
        }

        guard let image = ctx.makeImage() else { return }
        layer?.contents = image
    }
}
