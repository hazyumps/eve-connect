import AppKit

// Original vector artwork: a luminous terminal at the center of a small network.
// Render every macOS icon size from geometry, with no external assets or fonts.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = output.appendingPathComponent("EVEConnect.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func line(_ points: [NSPoint], width: CGFloat, ink: NSColor, glow: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    if glow > 0 {
        let shadow = NSShadow()
        shadow.shadowColor = ink.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = glow
        shadow.shadowOffset = .zero
        shadow.set()
    }
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    ink.setStroke()
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon() {
    let teal = color(0x53F4D4)
    let blue = color(0x54BCFF)
    let violet = color(0xB59AFF)
    let tile = rounded(NSRect(x: 56, y: 56, width: 912, height: 912), 204)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000A20, alpha: 0.4)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x0C1426).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x233B53), color(0x101C31), color(0x101528)])!.draw(in: tile, angle: -65)
    color(0x7194B3, alpha: 0.28).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    // Network traces enter the terminal from three directions.
    line([NSPoint(x: 216, y: 730), NSPoint(x: 320, y: 730), NSPoint(x: 392, y: 658)], width: 18, ink: teal, glow: 20)
    line([NSPoint(x: 808, y: 730), NSPoint(x: 704, y: 730), NSPoint(x: 632, y: 658)], width: 18, ink: blue, glow: 20)
    line([NSPoint(x: 512, y: 338), NSPoint(x: 512, y: 216)], width: 18, ink: violet, glow: 20)

    let panel = rounded(NSRect(x: 218, y: 322, width: 588, height: 370), 72)
    NSGradient(colors: [color(0x172D42), color(0x091423)])!.draw(in: panel, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    panel.addClip()
    let border = rounded(NSRect(x: 224, y: 328, width: 576, height: 358), 66)
    color(0x76D9E3, alpha: 0.68).setStroke()
    border.lineWidth = 8
    border.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Bold terminal prompt stays recognizable at small Dock/Finder sizes.
    line([NSPoint(x: 338, y: 580), NSPoint(x: 432, y: 502), NSPoint(x: 338, y: 424)], width: 38, ink: teal, glow: 18)
    line([NSPoint(x: 520, y: 426), NSPoint(x: 667, y: 426)], width: 34, ink: blue, glow: 18)

    for (point, ink) in [(NSPoint(x: 216, y: 730), teal), (NSPoint(x: 808, y: 730), blue), (NSPoint(x: 512, y: 206), violet)] {
        let ring = NSBezierPath(ovalIn: NSRect(x: point.x - 36, y: point.y - 36, width: 72, height: 72))
        color(0x14233A).setFill()
        ring.fill()
        ink.setStroke()
        ring.lineWidth = 12
        ring.stroke()
        ink.setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)).fill()
    }
}

func png(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(size) / 1024)
    scale.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try png(size: base * scale).write(to: iconset.appendingPathComponent(name))
    }
}
try png(size: 512).write(to: output.appendingPathComponent("icon-preview.png"))
