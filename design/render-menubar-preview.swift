// Renders design/menubar-preview.png from the menu bar glyph drawings.
//
//   swift design/render-menubar-preview.swift
//
// Uses only AppKit. Every glyph is rasterized at the exact pixel size a menu bar
// of that backing scale would draw (height in points x scale), tinted black on a
// light bar and white on a dark bar like a template image, and copied into the
// sheet without any resampling, so one pixel of the sheet is one pixel on screen.
// The column marked "native" is the drawing's own height; the others scale it.
// The first block is the SF Symbol the status item used before, for comparison.

import AppKit

let designDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
/// `file` is an SVG in this folder, or "symbol:<name>" for an SF Symbol at its default size.
let candidates: [(title: String, file: String, nativeHeight: Double)] = [
    ("Before: SF Symbol magnifyingglass", "symbol:magnifyingglass", 15),
    ("Candidate 1: slanted A", "menubar-icon-slanted.svg", 16),
    ("Candidate 2: upright A", "menubar-icon-upright.svg", 16),
    ("Candidate 3: solid lens", "menubar-icon-solid.svg", 16),
]
let sizes: [Double] = [15, 16, 18, 22]
let scales: [Int] = [1, 2]
let barHeightPoints = 24
let cellWidth = 96          // pixels, in both scales
let cellGap = 4
let zoom = 4                // magnification of the zoom section (1x pixels only)

struct Bar {
    let label: String
    let background: (UInt8, UInt8, UInt8)
    let ink: (UInt8, UInt8, UInt8)
}
let bars = [
    Bar(label: "Light bar", background: (236, 236, 238), ink: (0, 0, 0)),
    Bar(label: "Dark bar", background: (40, 40, 43), ink: (255, 255, 255)),
]

// MARK: Pixel buffers

struct Raster {
    var width: Int
    var height: Int
    var alpha: [UInt8]   // one byte per pixel
}

func loadImage(_ file: String) -> NSImage {
    if file.hasPrefix("symbol:") {
        let name = String(file.dropFirst("symbol:".count))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { fatalError("no symbol \(name)") }
        return image
    }
    let url = designDirectory.appendingPathComponent(file)
    guard let image = NSImage(contentsOf: url) else { fatalError("cannot load \(url.path)") }
    return image
}

/// Rasterizes the drawing at height x scale pixels and keeps its alpha channel.
func rasterize(_ file: String, heightPoints: Double, scale: Int) -> Raster {
    let image = loadImage(file)
    let heightPixels = Int((heightPoints * Double(scale)).rounded())
    let widthPixels = Int((heightPoints * image.size.width / image.size.height * Double(scale)).rounded())
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: widthPixels, pixelsHigh: heightPixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: widthPixels, height: heightPixels).fill(using: .copy)
    image.draw(in: NSRect(x: 0, y: 0, width: widthPixels, height: heightPixels))
    NSGraphicsContext.restoreGraphicsState()
    var alpha = [UInt8](repeating: 0, count: widthPixels * heightPixels)
    let data = rep.bitmapData!
    for y in 0..<heightPixels {
        for x in 0..<widthPixels {
            alpha[y * widthPixels + x] = data[y * rep.bytesPerRow + x * 4 + 3]
        }
    }
    return Raster(width: widthPixels, height: heightPixels, alpha: alpha)
}

// MARK: Sheet layout

let labelColumn = 64
let margin = 20
let blockWidth = sizes.count * cellWidth + (sizes.count - 1) * cellGap
let blockGap = 28
let sheetWidth = margin + labelColumn + candidates.count * blockWidth + (candidates.count - 1) * blockGap + margin

let labelFont = NSFont.systemFont(ofSize: 11)
let titleFont = NSFont.boldSystemFont(ofSize: 12)
let smallFont = NSFont.systemFont(ofSize: 10)
let textColor = NSColor(white: 0.2, alpha: 1)
let mutedColor = NSColor(white: 0.45, alpha: 1)

// Rows, top to bottom: (bar, scale) pairs, then the zoom section.
struct Row { var bar: Bar; var scale: Int; var top: Int; var stripHeight: Int }
var rows: [Row] = []
var y = margin + 18 + 22       // sheet title + candidate titles
for bar in bars {
    for scale in scales {
        let h = barHeightPoints * scale
        rows.append(Row(bar: bar, scale: scale, top: y, stripHeight: h))
        y += h + 16 + 8        // strip, size labels, gap
    }
    y += 6
}
let zoomTitleTop = y + 4
y += 4 + 18
let zoomRowHeight = 22 * zoom + 8
var zoomTops: [Int] = []
for _ in bars {
    zoomTops.append(y)
    y += zoomRowHeight + 16 + 8
}
let sheetHeight = y + margin - 10

// MARK: Canvas

let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: sheetWidth, pixelsHigh: sheetHeight,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let pixels = sheet.bitmapData!
let rowBytes = sheet.bytesPerRow

func put(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) {
    guard x >= 0, y >= 0, x < sheetWidth, y < sheetHeight else { return }
    let o = y * rowBytes + x * 4
    pixels[o] = c.0; pixels[o + 1] = c.1; pixels[o + 2] = c.2; pixels[o + 3] = 255
}
func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: (UInt8, UInt8, UInt8)) {
    for j in y..<(y + h) { for i in x..<(x + w) { put(i, j, c) } }
}
func blend(_ r: Raster, atX x0: Int, y y0: Int, bar: Bar, zoom z: Int = 1) {
    for j in 0..<r.height {
        for i in 0..<r.width {
            let a = Int(r.alpha[j * r.width + i])
            if a == 0 { continue }
            for dj in 0..<z {
                for di in 0..<z {
                    let x = x0 + i * z + di, yy = y0 + j * z + dj
                    let o = yy * rowBytes + x * 4
                    func mix(_ bg: UInt8, _ ink: UInt8) -> UInt8 {
                        UInt8((Int(bg) * (255 - a) + Int(ink) * a + 127) / 255)
                    }
                    pixels[o] = mix(pixels[o], bar.ink.0)
                    pixels[o + 1] = mix(pixels[o + 1], bar.ink.1)
                    pixels[o + 2] = mix(pixels[o + 2], bar.ink.2)
                }
            }
        }
    }
}

fill(0, 0, sheetWidth, sheetHeight, (250, 250, 250))

// Glyph rasters, drawn once per (candidate, size, scale).
func glyphs(_ file: String, scale: Int, sizes: [Double]) -> [Raster] {
    sizes.map { rasterize(file, heightPoints: $0, scale: scale) }
}

for (index, candidate) in candidates.enumerated() {
    let blockLeft = margin + labelColumn + index * (blockWidth + blockGap)
    for row in rows {
        let rasters = glyphs(candidate.file, scale: row.scale, sizes: sizes)
        for (k, raster) in rasters.enumerated() {
            let x = blockLeft + k * (cellWidth + cellGap)
            fill(x, row.top, cellWidth, row.stripHeight, row.bar.background)
            let gx = x + (cellWidth - raster.width) / 2
            let gy = row.top + (row.stripHeight - raster.height) / 2
            blend(raster, atX: gx, y: gy, bar: row.bar)
        }
    }
    // Zoom section: the 1x renderings, nearest-neighbour magnified.
    for (b, bar) in bars.enumerated() {
        for (k, size) in sizes.enumerated() {
            let raster = rasterize(candidate.file, heightPoints: size, scale: 1)
            let x = blockLeft + k * (cellWidth + cellGap)
            fill(x, zoomTops[b], cellWidth, zoomRowHeight, bar.background)
            let gx = x + (cellWidth - raster.width * zoom) / 2
            let gy = zoomTops[b] + (zoomRowHeight - raster.height * zoom) / 2
            blend(raster, atX: gx, y: gy, bar: bar, zoom: zoom)
        }
    }
}

// MARK: Text

func sizeLabel(_ size: Double, _ nativeHeight: Double) -> String {
    "\(Int(size)) pt" + (size == nativeHeight ? " native" : "")
}

func text(_ s: String, x: Int, top: Int, font: NSFont = labelFont, color: NSColor = textColor) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    // AppKit's origin is bottom-left; `top` is measured from the top edge.
    (s as NSString).draw(at: NSPoint(x: x, y: sheetHeight - top - Int(font.pointSize) - 3), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
}

text("One sheet pixel is one screen pixel: 1x rows are drawn as a 1x display draws them, 2x rows as a Retina display does.",
     x: margin, top: margin - 8, font: smallFont, color: mutedColor)
for (index, candidate) in candidates.enumerated() {
    let blockLeft = margin + labelColumn + index * (blockWidth + blockGap)
    text(candidate.title, x: blockLeft, top: margin + 14, font: titleFont)
    for row in rows {
        for (k, size) in sizes.enumerated() {
            let x = blockLeft + k * (cellWidth + cellGap)
            text(sizeLabel(size, candidate.nativeHeight), x: x, top: row.top + row.stripHeight + 2, font: smallFont, color: mutedColor)
        }
    }
    for b in 0..<bars.count {
        for (k, size) in sizes.enumerated() {
            let x = blockLeft + k * (cellWidth + cellGap)
            text(sizeLabel(size, candidate.nativeHeight), x: x, top: zoomTops[b] + zoomRowHeight + 2, font: smallFont, color: mutedColor)
        }
    }
}
for row in rows {
    text(row.bar.label, x: margin, top: row.top + 2)
    text("\(row.scale)x", x: margin, top: row.top + 17, color: mutedColor)
}
text("1x pixels magnified \(zoom)x", x: margin, top: zoomTitleTop, font: titleFont)
for (b, bar) in bars.enumerated() {
    text(bar.label, x: margin, top: zoomTops[b] + 2)
}

// MARK: Output

let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : designDirectory.appendingPathComponent("menubar-preview.png")
let png = sheet.representation(using: .png, properties: [:])!
try png.write(to: output)
print("wrote \(output.path) (\(sheetWidth)x\(sheetHeight))")
