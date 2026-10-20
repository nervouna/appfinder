// Draws the app icon artwork, design/icon.png: a 1024x1024 PNG on the macOS icon grid (an
// 824 pt rounded square with a 100 pt margin), in the palette of the owner's other menu bar
// apps: a cream tile, a dark brown magnifying glass, and a blue "A" in its lens for the ABC lock.
//
// Usage: swift scripts/draw-icon.swift <output.png>

import AppKit

let size: CGFloat = 1024
let cream = NSColor(srgbRed: 0.957, green: 0.902, blue: 0.808, alpha: 1)
let brown = NSColor(srgbRed: 0.290, green: 0.204, blue: 0.157, alpha: 1)
let blue = NSColor(srgbRed: 0.255, green: 0.522, blue: 0.894, alpha: 1)
let lensFill = NSColor(srgbRed: 0.992, green: 0.973, blue: 0.937, alpha: 1)

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/draw-icon.swift <output.png>\n".utf8))
    exit(2)
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    cream.setFill()
    tile.fill()

    // The lens, centered up and to the left, and the handle towards the bottom right.
    let center = NSPoint(x: 462, y: 452)
    let radius: CGFloat = 214
    let handle = NSBezierPath()
    let angle = CGFloat.pi / 4
    handle.move(to: NSPoint(x: center.x + cos(angle) * (radius + 20), y: center.y + sin(angle) * (radius + 20)))
    handle.line(to: NSPoint(x: 756, y: 746))
    handle.lineWidth = 92
    handle.lineCapStyle = .round
    brown.setStroke()
    handle.stroke()

    let lens = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    lensFill.setFill()
    lens.fill()
    lens.lineWidth = 60
    brown.setStroke()
    lens.stroke()

    let font = NSFont.systemFont(ofSize: 268, weight: .heavy)
    let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 268) } ?? font
    let text = NSAttributedString(string: "A", attributes: [.font: rounded, .foregroundColor: blue])
    let bounds = text.boundingRect(with: NSSize(width: 1000, height: 1000), options: [.usesLineFragmentOrigin])
    text.draw(at: NSPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2 - 6))
    return true
}

// Drawn into a 1x bitmap so that the PNG is exactly 1024 pixels wide on any display.
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
