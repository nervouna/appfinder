#!/usr/bin/env bash
# Checks the icon of a built app and renders it the way the system shows it.
#
# Usage: scripts/check-icon-render.sh [<app>]   (default: build/AppFinder.app, see scripts/build.sh)
#
# Fails unless the bundle names the icon (CFBundleIconName and CFBundleIconFile are AppIcon),
# has Contents/Resources/AppIcon.icns, and its Assets.car holds the AppIcon stack for the light,
# dark and tinted appearances. Then copies the app to a new directory under build/ (the system
# caches an app's icon by its path, so only a copy at a fresh path shows the icon the app has
# now) and writes the icon that NSWorkspace returns for it, as Finder and the Dock draw it, at
# 512, 256, 128, 64, 32 and 16 px with the light and the dark appearance, to sheet.png there.
# Which variant the dark renders show follows the "Icon & widget style" in System Settings.

set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

if [[ $# -gt 1 ]]; then
    echo "Usage: scripts/check-icon-render.sh [<app>]" >&2
    exit 2
fi
app="${1:-$BUILD_DIR/$APP_NAME.app}"
[[ -d "$app" ]] || die "$app does not exist, run scripts/build.sh release first"

info="$app/Contents/Info.plist"
for key in CFBundleIconName CFBundleIconFile; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$info" 2>/dev/null)" || die "$key is missing from $info"
    [[ "$value" == AppIcon ]] || die "$key is '$value', not AppIcon"
done
[[ -f "$app/Contents/Resources/AppIcon.icns" ]] || die "$app has no Contents/Resources/AppIcon.icns"

catalog_info="$(xcrun --sdk macosx assetutil --info "$app/Contents/Resources/Assets.car")" \
    || die "cannot read $app/Contents/Resources/Assets.car"
for appearance in NSAppearanceNameAqua NSAppearanceNameDarkAqua ISAppearanceTintable; do
    # Each rendition is a JSON object; keep the ones named AppIcon and look for the appearance.
    grep -q "\"$appearance\"" <<<"$(awk '/^  \{/ { block = "" } { block = block $0 "\n" } /^  \}/ && block ~ /"Name" : "AppIcon"/ { printf "%s", block }' <<<"$catalog_info")" \
        || die "Assets.car has no AppIcon for the $appearance appearance"
done
log "The bundle has AppIcon in Info.plist, AppIcon.icns and Assets.car (light, dark, tinted)"

build_icon_tool
mkdir -p "$BUILD_DIR"
work="$(mktemp -d "$BUILD_DIR/icon-check.XXXXXX")"
ditto "$app" "$work/$APP_NAME.app"
"$ICON_TOOL" render-app "$work/$APP_NAME.app" "$work" 512 256 128 64 32 16
log "Wrote ${work#"$APPFINDER_ROOT"/}/sheet.png"
