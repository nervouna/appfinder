# Design files

| File | What it is |
|---|---|
| `icon-concepts.png` | The candidates the owner chose from (2026-10-21), generated images rendered through Icon Composer at 256, 64 and 32 px on a light and a dark background. "A, magnifier A" was chosen; `App/AppIcon.icon` is its vector redraw. |
| `icon-preview.png` | `App/AppIcon.icon` rendered by `ictool` in all six appearances, and at 128 to 16 px. Written by `scripts/render-icon.sh`. |

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
