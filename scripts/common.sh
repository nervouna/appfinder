# Shared helpers for the AppFinder scripts. Sourced by them, not executed.
#
# shellcheck shell=bash disable=SC2034

# Absolute path of the checkout (or git worktree) that contains this script, so
# the scripts behave the same from any working directory.
APPFINDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD_DIR="$APPFINDER_ROOT/build"
APP_NAME="AppFinder"
INSTALLED_APP="/Applications/$APP_NAME.app"
# The test fixture app (Debug builds only, see scripts/check-input-source.sh).
FIXTURE_NAME="AppFinderFixture"

die() {
    echo "error: $*" >&2
    exit 1
}

log() {
    echo "==> $*" >&2
}

# Reads the signing settings. They are never part of the repository: the file
# named by APPFINDER_SIGNING_ENV, or ${XDG_CONFIG_HOME:-$HOME/.config}/appfinder/signing.env,
# is the only source. A missing file means ad-hoc signing.
#
# Sets SIGN_ENV_FILE, SIGN_IDENTITY and SIGN_TEAM (the last two are empty for ad-hoc).
load_signing_env() {
    SIGN_ENV_FILE="${APPFINDER_SIGNING_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/appfinder/signing.env}"

    # Do not let values inherited from the caller's environment override the file.
    unset APPFINDER_CODESIGN_IDENTITY APPFINDER_TEAM_ID

    if [[ -r "$SIGN_ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$SIGN_ENV_FILE"
    elif [[ -n "${APPFINDER_SIGNING_ENV:-}" ]]; then
        log "signing env file '$SIGN_ENV_FILE' is not readable"
    fi

    SIGN_IDENTITY="${APPFINDER_CODESIGN_IDENTITY:-}"
    SIGN_TEAM="${APPFINDER_TEAM_ID:-}"

    if [[ -n "$SIGN_IDENTITY" && -z "$SIGN_TEAM" ]]; then
        die "APPFINDER_CODESIGN_IDENTITY is set but APPFINDER_TEAM_ID is not (see $SIGN_ENV_FILE)"
    fi
}
