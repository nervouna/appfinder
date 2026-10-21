// Helper for scripts/render-icon.sh and scripts/check-icon-render.sh. Draws contact sheets of
// icon renders and renders the icon the system shows for a built app.
//
// Usage:
//   icon-tool sheet <out.png> <title> <dir>
//       Lays out the renders that render-icon.sh wrote to <dir>: the six appearances at 256 px
//       (<Appearance>-256.png) in the first row, then Default and Dark at 128, 64, 32 and 16 px
//       (<Appearance>-<size>.png) at their pixel size, so one sheet pixel is one render pixel.
//   icon-tool render-app <app> <outdir> <size>...
//       Writes the icon that NSWorkspace returns for the bundle, drawn at each size with the
//       light (Aqua) and the dark (Dark Aqua) appearance, to <outdir>/<light|dark>-<size>.png,
//       and a sheet of them on a light and a dark background to <outdir>/sheet.png.

import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("icon-tool: \(message)\n".utf8))
    exit(1)
}

/// A bitmap of the given pixel size (1 pt = 1 px), drawn into by `draw`.
func bitmap(width: Int, height: Int, _ draw: () -> Void) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else { fail("cannot make a \(width)x\(height) bitmap") }
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("cannot encode \(path)") }
    do {
        try png.write(to: URL(fileURLWithPath: path))
    } catch {
        fail("cannot write \(path): \(error.localizedDescription)")
    }
}

/// Draws the PNG at `path` at its pixel size with its bottom left corner at `origin`.
func drawPNG(_ path: String, at origin: NSPoint) {
    guard let image = NSImage(contentsOfFile: path), let rep = image.representations.first else {
        fail("cannot read \(path)")
    }
    image.draw(in: NSRect(x: origin.x, y: origin.y, width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)))
}

func label(_ text: String, at point: NSPoint, size: CGFloat = 13, color: NSColor) {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color,
    ]).draw(at: point)
}

let pad: CGFloat = 24
let labelHeight: CGFloat = 22
let lightBackground = NSColor(white: 0.93, alpha: 1)
let darkBackground = NSColor(white: 0.12, alpha: 1)

// MARK: - Sheet of the document's renders

func sheet(out: String, title: String, directory: String) {
    let appearances = ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"]
    let smallAppearances = ["Default", "Dark"]
    let smallSizes: [CGFloat] = [128, 64, 32, 16]
    let titleHeight: CGFloat = 40
    let width = pad + CGFloat(appearances.count) * (256 + pad)
    let smallRowHeight = 128 + labelHeight + pad
    let height = titleHeight + 256 + labelHeight + pad + smallRowHeight + pad
    let rep = bitmap(width: Int(width), height: Int(height)) {
        lightBackground.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let ink = NSColor(white: 0.2, alpha: 1)
        label(title, at: NSPoint(x: pad, y: height - titleHeight + 8), size: 17, color: ink)

        var y = height - titleHeight - 256
        for (i, appearance) in appearances.enumerated() {
            let x = pad + CGFloat(i) * (256 + pad)
            drawPNG("\(directory)/\(appearance)-256.png", at: NSPoint(x: x, y: y))
            label(appearance, at: NSPoint(x: x, y: y - labelHeight), color: ink)
        }

        // Default on the light half of the row, Dark on a dark panel on the right half.
        y -= labelHeight + pad + 128
        let half = width / 2
        darkBackground.setFill()
        NSRect(x: half, y: 0, width: half, height: y + 128 + pad / 2).fill()
        for (column, appearance) in smallAppearances.enumerated() {
            var x = (column == 0 ? 0 : half) + pad
            for size in smallSizes {
                drawPNG("\(directory)/\(appearance)-\(Int(size)).png", at: NSPoint(x: x, y: y + (128 - size) / 2))
                label("\(appearance) \(Int(size))", at: NSPoint(x: x, y: y - labelHeight),
                      color: column == 0 ? ink : NSColor(white: 0.85, alpha: 1))
                x += max(size, 80) + pad
            }
        }
    }
    write(rep, to: out)
}

// MARK: - The icon the system shows for an app

func renderApp(app: String, outDirectory: String, sizes: [Int]) {
    let icon = NSWorkspace.shared.icon(forFile: app)
    let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
    for (name, appearanceName) in appearances {
        guard let appearance = NSAppearance(named: appearanceName) else { fail("no \(appearanceName) appearance") }
        for size in sizes {
            var rep: NSBitmapImageRep?
            appearance.performAsCurrentDrawingAppearance {
                rep = bitmap(width: size, height: size) {
                    icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero,
                              operation: .sourceOver, fraction: 1)
                }
            }
            write(rep!, to: "\(outDirectory)/\(name)-\(size).png")
        }
    }

    // The renders at their pixel size, the light ones on a light band, the dark ones on a dark band.
    let largest = CGFloat(sizes.max() ?? 0)
    let column = { (size: Int) in max(CGFloat(size), 72) }
    let width = pad + sizes.reduce(0) { $0 + column($1) + pad }
    let band = pad + largest + labelHeight + pad
    let rep = bitmap(width: Int(width), height: Int(band * 2)) {
        for (row, (name, _)) in appearances.enumerated() {
            let base = row == 0 ? band : 0
            (row == 0 ? lightBackground : darkBackground).setFill()
            NSRect(x: 0, y: base, width: width, height: band).fill()
            var x = pad
            for size in sizes {
                let y = base + labelHeight + pad + (largest - CGFloat(size)) / 2
                drawPNG("\(outDirectory)/\(name)-\(size).png", at: NSPoint(x: x, y: y))
                label("\(name) \(size)", at: NSPoint(x: x, y: base + pad / 2),
                      color: row == 0 ? NSColor(white: 0.2, alpha: 1) : NSColor(white: 0.85, alpha: 1))
                x += column(size) + pad
            }
        }
    }
    write(rep, to: "\(outDirectory)/sheet.png")
}

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "" {
case "sheet" where arguments.count == 5:
    sheet(out: arguments[2], title: arguments[3], directory: arguments[4])
case "render-app" where arguments.count > 4:
    let sizes = arguments[4...].map { argument -> Int in
        guard let size = Int(argument), size > 0 else { fail("not a size: \(argument)") }
        return size
    }
    renderApp(app: arguments[2], outDirectory: arguments[3], sizes: sizes)
default:
    fail("usage: icon-tool sheet <out.png> <title> <dir> | icon-tool render-app <app> <outdir> <size>...")
}
