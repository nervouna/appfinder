# Design files

| File | What it is |
|---|---|
| `icon-concepts.png` | The candidates the owner chose from (2026-10-21), generated images rendered through Icon Composer at 256, 64 and 32 px on a light and a dark background. "A, magnifier A" was chosen; `App/AppIcon.icon` is its vector redraw. |
| `icon-preview.png` | `App/AppIcon.icon` rendered by `ictool` in all six appearances, and at 128 to 16 px. Written by `scripts/render-icon.sh`. |
| `menubar-icon-slanted.svg` | Menu bar glyph, candidate 1 (slanted A): 16 × 16 pt. Chosen by the owner (2026-10-21); the app ships it as `MenuBarIcon`. |
| `menubar-icon-upright.svg` | Menu bar glyph, candidate 2 (upright A): 16 × 16 pt. Not used by the app. |
| `menubar-icon-solid.svg` | Menu bar glyph, candidate 3 (solid lens, the A cut out): 16 × 16 pt. Not used by the app. |
| `menubar-preview.png` | The SF Symbol the status item showed before and the three candidates, at 15, 16, 18 and 22 pt, at 1x and 2x, on a light and a dark menu bar, plus a magnified view of the 1x pixels. |
| `render-menubar-preview.swift` | Script that renders `menubar-preview.png` from the drawings in its `candidates` array. |

## The app icon

`App/AppIcon.icon` is an Icon Composer document. Xcode compiles it into `Assets.car` (light, dark and tinted renditions) and `AppIcon.icns`; the app's `ASSETCATALOG_COMPILER_APPICON_NAME` is `AppIcon`, and the `App` folder is a synchronized group, so nothing in the project names the file.

It is an Icon Composer document rather than a PNG icon set because the app requires macOS 26, where this is the native format: the system draws the icon shape and margin itself, and it renders the Dark, Clear and Tinted icon styles from separate layers. A flat PNG gets the same picture in every style. ClickClick and InkFlow use Icon Composer documents too.

The picture: a magnifying glass, its lens showing a blue capital A, the ABC input source that the panel locks to. It follows Piccolo's style: cream tile, espresso-brown outline, a caramel accent and one clear blue.

### Layers

One group, four SVG layers on a 1024 × 1024 canvas, top to bottom. The canvas is the whole icon shape; Icon Composer cuts the rounded square out of it. The fill behind them is the document's.

| Layer | Shape | Light | Dark |
|---|---|---|---|
| `letter.svg` | A drawn as strokes with round joins and caps: legs 108 wide from the feet at x 328 and 620 (y 600) to a flat apex 20 wide (x 464–484, y 324); crossbar 72 wide at y 544. Its box (y 270–654) sits 12 above the lens centre, as the weight of a triangle is low. | `#3F88E2` | `#5B9EF0` |
| `grip.svg` | 160 × 72 rounded bar on the handle, 36 from its sides and end. | `#B98258` | same |
| `frame.svg` | Ring around (474, 474), radius 316 on its centre line, 72 wide; handle 144 wide at 45°, from the ring's centre line to 536 from the lens centre, round end. | `#573A2C` | `#E3CFB2` |
| `lens.svg` | Disc under the ring, radius 316. | `#FDF8EF` | `#40322B` |
| fill | | `#F7EAD5` | `#2E231E` |

The light colours are the SVGs' own; the dark ones are `fill-specializations` in `icon.json`. The magnifier's box (x and y 122–904) is centred on the canvas, and its handle end stays well inside the shape's rounded corner. Every layer has glass off; the group keeps Icon Composer's specular edge and neutral shadow, and translucency is off.

## Changing the icon

Edit the SVGs or `icon.json` by hand, or open `App/AppIcon.icon` in Icon Composer (`Xcode.app/Contents/Applications/Icon Composer.app`). Then:

1. `scripts/render-icon.sh` renders `design/icon-preview.png`; commit it with the change.
2. `scripts/build.sh release`, then `scripts/check-icon-render.sh`: it checks that the bundle carries the icon (Info.plist, `AppIcon.icns`, `Assets.car` for the light, dark and tinted appearances) and writes the icon as Finder and the Dock draw it, at 512 to 16 px, to `build/icon-check.*/sheet.png`. Which style those renders show follows the "Icon & widget style" in System Settings, not the drawing appearance.

## The menu bar glyph

The status item used to show the SF Symbol `magnifyingglass`, the same picture as Spotlight's. It now shows the app icon's magnifier reduced to one colour, with the A in its lens. All drawings are black on transparent, one SVG unit per point, with no colour, shadow or gradient, on a 16 pt grid, 16 × 16 pt. The ring and the letter are drawn with 1 pt lines, and every straight horizontal edge sits on a whole point, so those edges are crisp at 1x; the ring, the handle and the A's legs are anti-aliased.

- Lens: a ring around (7, 7), outer radius 7 (x and y 0–14), inner radius 6.
- Handle: 2 pt wide at 45°, twice the ring as on the app icon, from the ring to a round end centred on (15, 15), so the glyph touches x = 16 and y = 16. Each SVG draws ring and handle as one outline minus the inner disc, so nothing overlaps under the even-odd rule.
- Letter (candidates 1 and 3): the app icon's A with 1 pt lines. Box x 3.5–10.5, y 3–10, half a point above the lens centre as on the icon. Flat apex x 6–8 on y 3–4, legs 1 pt thick across, crossbar y 7–8, feet cut flat on y = 10.

The candidates differ in the letter and the lens:

- Candidate 1, slanted A (ships): the ring with the icon's A.
- Candidate 2, upright A: the ring with an A whose legs are upright (x 4–5 and 9–10) and whose top corners are rounded (2 pt outside, 1 pt inside), so every edge but those corners is on a whole point. The crispest at 1x; it reads like a pixel-font A.
- Candidate 3, solid lens: a solid disc with candidate 1's A cut out; its counter stays filled. The most unlike Spotlight's magnifier, and heavier than most menu bar glyphs.

## How `MenuBarIcon` is made

`App/Assets.xcassets/MenuBarIcon.imageset/` holds a copy of `menubar-icon-slanted.svg` (under the name `menubar-icon.svg`) and a `Contents.json` that asks for the vector data to be preserved and for the template rendering intent:

```json
"properties" : {
  "preserves-vector-representation" : true,
  "template-rendering-intent" : "template"
}
```

The system tints a template image for light, dark and highlighted menu bars, so the SVG stays black on transparent. `App/StatusMenu.swift` loads it with `NSImage(named: "MenuBarIcon")` and sets the accessibility description. The image is 16 × 16 pt, and the square status item centres it. The asset catalog holds only this image set: the app icon stays in `App/AppIcon.icon`, and Xcode compiles both into the same `Assets.car`.

To change the glyph, edit `design/menubar-icon-slanted.svg`, copy it over the file in the image set (keep the file name `menubar-icon.svg`, `Contents.json` refers to it) and render the preview again. To ship another candidate, copy its SVG over the image set's `menubar-icon.svg`. Check the result with `scripts/build.sh release` and:

```sh
xcrun --sdk macosx assetutil --info build/AppFinder.app/Contents/Resources/Assets.car | grep -B12 '"Template Mode"'
```

which lists `MenuBarIcon` at 1x and 2x with `"Template Mode" : "template"` and `"Preserved Vector Representation" : true`, at 16 × 16 and 32 × 32 pixels.

## Rendering the preview

```sh
swift design/render-menubar-preview.swift [output.png]
```

It is Piccolo's script with AppFinder's candidates, and needs only AppKit. Each glyph is rasterized at the pixel size a menu bar of that scale would draw (height in points × scale), tinted black on the light bar and white on the dark bar like a template image, and copied into the sheet without resampling, so one sheet pixel is one screen pixel. The column marked "native" is the drawing's own height; the other columns scale it, so they show a size the menu bar does not draw. The first block is the SF Symbol, drawn by AppKit at its default size, 16 × 15 pt with its own margins. The drawings are listed in the script's `candidates` array, in the order they appear on the sheet, each with its native height.
