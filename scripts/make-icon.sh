#!/usr/bin/env bash
# Regenerates the app icon set, App/Assets.xcassets/AppIcon.appiconset, from the artwork in
# design/icon.png: every macOS size (16, 32, 128, 256 and 512 pt at 1x and 2x), each
# downscaled from the source with sips, plus the set's Contents.json.
#
# Usage: scripts/make-icon.sh [--draw]
#
# --draw first renders design/icon.png again with scripts/draw-icon.swift.

set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SOURCE="$APPFINDER_ROOT/design/icon.png"
ICON_SET="$APPFINDER_ROOT/App/Assets.xcassets/AppIcon.appiconset"

if [[ "${1:-}" == "--draw" ]]; then
    mkdir -p "$(dirname "$SOURCE")"
    swift "$APPFINDER_ROOT/scripts/draw-icon.swift" "$SOURCE"
elif [[ $# -gt 0 ]]; then
    echo "Usage: scripts/make-icon.sh [--draw]" >&2
    exit 2
fi
[[ -f "$SOURCE" ]] || die "the artwork ${SOURCE#"$APPFINDER_ROOT"/} does not exist (run with --draw)"

rm -rf "$ICON_SET"
mkdir -p "$ICON_SET"
images=""
for points in 16 32 128 256 512; do
    for scale in 1 2; do
        pixels=$((points * scale))
        if ((scale == 1)); then
            name="icon_${points}x${points}.png"
        else
            name="icon_${points}x${points}@2x.png"
        fi
        sips -z "$pixels" "$pixels" "$SOURCE" --out "$ICON_SET/$name" >/dev/null
        images+="    { \"filename\" : \"$name\", \"idiom\" : \"mac\", \"scale\" : \"${scale}x\", \"size\" : \"${points}x${points}\" },"$'\n'
    done
done
cat >"$ICON_SET/Contents.json" <<EOF
{
  "images" : [
${images%,$'\n'}
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
cat >"$APPFINDER_ROOT/App/Assets.xcassets/Contents.json" <<'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
log "Wrote ${ICON_SET#"$APPFINDER_ROOT"/}"
