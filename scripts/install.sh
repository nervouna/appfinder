#!/usr/bin/env bash
# Builds the app, replaces /Applications/AppFinder.app and launches it.
#
# Usage: scripts/install.sh [debug|release]   (default: release)
#
# Only a Debug build hosts the control server that appfinderctl talks to.
#
# The login item and any permission the user grants are tied to the bundle ID and the
# signing identity, so only a build signed with the configured identity may be
# installed. Without one this script refuses before it builds or touches /Applications.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    echo "Usage: scripts/install.sh [debug|release]" >&2
}

if [[ $# -gt 1 ]]; then
    usage
    exit 2
fi

case "${1:-release}" in
    debug | release) configuration="${1:-release}" ;;
    *)
        usage
        exit 2
        ;;
esac

load_signing_env

if [[ -z "$SIGN_IDENTITY" ]]; then
    die "no signing identity configured, refusing to install an ad-hoc build over $INSTALLED_APP.
Set APPFINDER_CODESIGN_IDENTITY and APPFINDER_TEAM_ID in $SIGN_ENV_FILE
(or point APPFINDER_SIGNING_ENV at a file that sets them)."
fi

"$SCRIPT_DIR/build.sh" "$configuration"

built_app="$BUILD_DIR/$APP_NAME.app"
if codesign -dv "$built_app" 2>&1 | grep -q '^Signature=adhoc'; then
    die "$built_app is ad-hoc signed, refusing to install it"
fi

# Stage next to the destination so that the final step is a single rename.
staging="$(mktemp -d "/Applications/.$APP_NAME-install.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$built_app" "$staging/$APP_NAME.app"
codesign --verify --strict --deep "$staging/$APP_NAME.app"

# LaunchServices lists the app by this ID; read it here, before anything is quit or replaced.
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$staging/$APP_NAME.app/Contents/Info.plist" 2>/dev/null || true)"
[[ -n "$bundle_id" ]] || die "$built_app has no CFBundleIdentifier"

if pgrep -x "$APP_NAME" >/dev/null; then
    log "Quitting running $APP_NAME"
    pkill -TERM -x "$APP_NAME" || true
    for _ in $(seq 1 50); do
        pgrep -x "$APP_NAME" >/dev/null || break
        sleep 0.1
    done
    if pgrep -x "$APP_NAME" >/dev/null; then
        die "$APP_NAME is still running after SIGTERM, not replacing it"
    fi
fi

log "Installing $INSTALLED_APP"
rm -rf "$INSTALLED_APP"
mv "$staging/$APP_NAME.app" "$INSTALLED_APP"
codesign --verify --strict --deep "$INSTALLED_APP"

# Time in seconds with a fraction. Bash 3.2, the shell macOS ships, has no sub-second clock;
# perl is part of macOS. Kept at full precision so that elapsed() rounds only once.
now() {
    /usr/bin/perl -MTime::HiRes=time -e 'printf "%.6f", time'
}

# elapsed <start>: the seconds since <start>, a value that now() gave.
elapsed() {
    /usr/bin/perl -MTime::HiRes=time -e 'printf "%.1f", time - $ARGV[0]' "$1"
}

# registry_lines: what LaunchServices lists for the app, one line per instance; nothing when
# it lists none.
registry_lines() {
    /usr/bin/lsappinfo find "bundleid=$bundle_id" 2>/dev/null || true
}

# listed: whether LaunchServices lists an instance of the app (its lines start with "ASN:").
listed() {
    local lines
    lines="$(registry_lines)"
    [[ "$lines" == ASN:* || "$lines" == *$'\n'ASN:* ]]
}

# running: whether a AppFinder process exists.
running() {
    pgrep -x "$APP_NAME" >/dev/null
}

# wait_unlisted: waits for LaunchServices to forget the app, at most 10 s, polled every 0.1 s.
# It logs only when it had to wait. Returns 1 when the app is still listed after that.
#
# While LaunchServices still lists the instance that quit, an open goes to that dead instance:
# it fails with error -600 and can leave the desktop without a frontmost application.
wait_unlisted() {
    local polls=0 started
    if ! listed; then
        return 0
    fi
    started="$(now)"
    log "LaunchServices still lists $bundle_id, waiting for it to forget the old instance"
    while listed; do
        if ((polls >= 100)); then
            log "LaunchServices still lists $bundle_id after $(elapsed "$started") s: $(registry_lines | tr '\n' ' ')"
            return 1
        fi
        sleep 0.1
        polls=$((polls + 1))
    done
    log "LaunchServices forgot $bundle_id after $(elapsed "$started") s"
}

# wait_listed: waits for LaunchServices to list an instance of the app, at most 10 s, polled
# every 0.1 s.
wait_listed() {
    local polls=0
    until listed; do
        if ((polls >= 100)); then
            return 1
        fi
        sleep 0.1
        polls=$((polls + 1))
    done
}

# launch_installed_app: opens the installed app and checks that LaunchServices lists it.
# An attempt does not run open while LaunchServices lists an instance: a listed instance that
# is running is the app already up, and a listed one that is not is the stale entry of the old
# process, which wait_unlisted waits for. A failed open, or no instance listed within 10 s, is
# logged, and the next attempt follows after a pause. Five attempts at most; then it dies with
# what was seen.
launch_installed_app() {
    local attempt=0 seen="" out started
    while ((attempt < 5)); do
        attempt=$((attempt + 1))
        # An instance that an earlier open started may only have come up late.
        if running && listed; then
            log "$APP_NAME is running: LaunchServices lists $bundle_id"
            return 0
        fi
        if ! wait_unlisted; then
            seen="LaunchServices still lists $bundle_id as running, so open was not run"
        else
            log "Launching $INSTALLED_APP (attempt $attempt of 5)"
            started="$(now)"
            if out="$(open "$INSTALLED_APP" 2>&1)"; then
                if wait_listed; then
                    log "$APP_NAME is running: LaunchServices lists $bundle_id after $(elapsed "$started") s"
                    return 0
                fi
                seen="open succeeded, but LaunchServices listed no instance of $bundle_id within 10 s"
            else
                seen="open failed: ${out:-no output}"
            fi
        fi
        log "attempt $attempt of 5 failed: $seen"
        if ((attempt < 5)); then
            sleep 0.5
        fi
    done
    die "$APP_NAME did not start after 5 attempts; last seen: $seen. $INSTALLED_APP is installed but not running."
}

launch_installed_app
