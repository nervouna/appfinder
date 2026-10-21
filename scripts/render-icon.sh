#!/usr/bin/env bash
# Renders the app icon document, App/AppIcon.icon, with Icon Composer's ictool in every
# appearance the system draws it in (Default, Dark, Clear and Tinted, each light and dark) at
# 256 px, and Default and Dark at 128, 64, 32 and 16 px, and lays the renders out in
# design/icon-preview.png. Run it after changing the document and commit the preview with it.
#
# Usage: scripts/render-icon.sh [<out.png>]   (default: design/icon-preview.png)
#
# The single renders stay in build/icon-preview/. ictool draws the document the way Icon
# Composer previews it: the icon shape fills the image, without the margin macOS adds around
# it in Finder or the Dock (see scripts/check-icon-render.sh for those).

set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [[ $# -gt 1 ]]; then
    echo "Usage: scripts/render-icon.sh [<out.png>]" >&2
    exit 2
fi
out="${1:-$APPFINDER_ROOT/design/icon-preview.png}"

ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
[[ -x "$ICTOOL" ]] || die "ictool not found at $ICTOOL (it ships with Xcode 26 or later)"
[[ -d "$APP_ICON" ]] || die "${APP_ICON#"$APPFINDER_ROOT"/} does not exist"

renders="$BUILD_DIR/icon-preview"
mkdir -p "$(dirname "$out")"
rm -rf "$renders"
mkdir -p "$renders"

# render <appearance> <pixels>
render() {
    "$ICTOOL" "$APP_ICON" --export-image --output-file "$renders/$1-$2.png" --platform macOS \
        --rendition "$1" --width "$2" --height "$2" --scale 1 >/dev/null \
        || die "ictool cannot render the $1 appearance at $2 px"
}

for appearance in Default Dark ClearLight ClearDark TintedLight TintedDark; do
    render "$appearance" 256
done
for appearance in Default Dark; do
    for pixels in 128 64 32 16; do
        render "$appearance" "$pixels"
    done
done

build_icon_tool
"$ICON_TOOL" sheet "$out" "App/AppIcon.icon, rendered by ictool $("$ICTOOL" --version | awk -F'"' '/short-bundle-version/ { print $4 }')" "$renders"
log "Wrote ${out#"$APPFINDER_ROOT"/}"
