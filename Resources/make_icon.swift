// Build-time tool (not part of the app target) that renders the KeyLocker
// app icon -- a keyboard glyph with a red lock badge -- to a single 1024x1024
// PNG. `build.sh` downsamples this master into the full .iconset and packs
// it into AppIcon.icns via `iconutil`.
//
// Usage: swift Resources/make_icon.swift <output.png>

import AppKit

let canvasSize: CGFloat = 1024

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("Usage: swift make_icon.swift <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let outputPath = CommandLine.arguments[1]

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize),
    pixelsHigh: Int(canvasSize),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write("Could not create bitmap.\n".data(using: .utf8)!)
    exit(1)
}
rep.size = NSSize(width: canvasSize, height: canvasSize)

guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    FileHandle.standardError.write("Could not create graphics context.\n".data(using: .utf8)!)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

// MARK: - Background (rounded square, subtle keycap-style gradient)

let inset: CGFloat = 40
let bgRect = NSRect(x: inset, y: inset, width: canvasSize - inset * 2, height: canvasSize - inset * 2)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 210, yRadius: 210)
let backgroundGradient = NSGradient(
    starting: NSColor(calibratedWhite: 0.97, alpha: 1),
    ending: NSColor(calibratedWhite: 0.80, alpha: 1)
)
backgroundGradient?.draw(in: bgPath, angle: -90)

NSColor(calibratedWhite: 0.60, alpha: 0.55).setStroke()
bgPath.lineWidth = 5
bgPath.stroke()

// MARK: - Keyboard glyph

let keyboardTint = NSColor(calibratedRed: 0.17, green: 0.19, blue: 0.23, alpha: 1)
if let keyboardBase = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: canvasSize * 0.50, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [keyboardTint]))
    if let keyboardImage = keyboardBase.withSymbolConfiguration(config) {
        let size = keyboardImage.size
        let rect = NSRect(
            x: (canvasSize - size.width) / 2,
            y: (canvasSize - size.height) / 2 - canvasSize * 0.02,
            width: size.width,
            height: size.height
        )
        keyboardImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

// MARK: - Red lock badge (overlapping the keyboard, bottom-right)

let badgeDiameter = canvasSize * 0.46
let badgeRect = NSRect(
    x: canvasSize - badgeDiameter - canvasSize * 0.05,
    y: canvasSize * 0.05,
    width: badgeDiameter,
    height: badgeDiameter
)

// White ring so the red badge reads clearly against the keyboard glyph.
let ringRect = badgeRect.insetBy(dx: -16, dy: -16)
NSColor.white.setFill()
NSBezierPath(ovalIn: ringRect).fill()

let badgeRed = NSColor(calibratedRed: 0.89, green: 0.15, blue: 0.18, alpha: 1)
badgeRed.setFill()
NSBezierPath(ovalIn: badgeRect).fill()

if let lockBase = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: badgeDiameter * 0.52, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let lockImage = lockBase.withSymbolConfiguration(config) {
        let size = lockImage.size
        let rect = NSRect(
            x: badgeRect.midX - size.width / 2,
            y: badgeRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        lockImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Could not encode PNG.\n".data(using: .utf8)!)
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    FileHandle.standardError.write("Write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
