#!/usr/bin/env bash
# Builds a notarized, stapled, distributable archive: build/release/AppFinder-<version>.zip
#
# Usage: scripts/release.sh [--skip-notarize | --publish [--notes-file FILE]]
#
# Steps: Developer ID release build (hardened runtime, secure timestamp, no
# get-task-allow), signature checks, notarization (xcrun notarytool submit --wait),
# stapling, a zip of the stapled app, and a final check of the app extracted from
# that zip. The signing and notary settings come from the signing env file (see
# scripts/common.sh); they are never part of the repository.
#
# --skip-notarize stops after the signature checks and zips the signed but
# un-notarized app, to rehearse everything except the upload. That archive is not
# fit for distribution.
# --publish also pushes the current main commit and its version tag, uploads the
# verified archive and checksum to a draft GitHub Release, then publishes it.
#
# The notary API key is passed to notarytool by path and is never read here. The
# issuer ID is read into a variable that is never printed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    echo "Usage: scripts/release.sh [--skip-notarize | --publish [--notes-file FILE]]" >&2
}

skip_notarize=false
publish=false
notes_file=""
while (($#)); do
    case "$1" in
        --skip-notarize) skip_notarize=true ;;
        --publish) publish=true ;;
        --notes-file)
            [[ $# -ge 2 && -n "$2" ]] || die "--notes-file needs a file path"
            notes_file="$2"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
    shift
done

if $publish && $skip_notarize; then
    die "--publish cannot be combined with --skip-notarize"
fi
if [[ -n "$notes_file" ]]; then
    $publish || die "--notes-file requires --publish"
    [[ -f "$notes_file" && -r "$notes_file" ]] || die "release notes are not readable: $notes_file"
fi

RELEASE_DIR="$BUILD_DIR/release"
commit_file="$RELEASE_DIR/release-commit"
reuse_archive=false

git_repo() { git -C "$APPFINDER_ROOT" "$@"; }

project_version() {
    sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' \
        "$APPFINDER_ROOT/AppFinder.xcodeproj/project.pbxproj" | sort -u
}

github_repo() {
    local url="$1" name
    case "$url" in
        git@github.com:*) name="${url#git@github.com:}" ;;
        https://github.com/*) name="${url#https://github.com/}" ;;
        ssh://git@github.com/*) name="${url#ssh://git@github.com/}" ;;
        *) die "origin must use a github.com URL, got: $url" ;;
    esac
    name="${name%.git}"
    [[ "$name" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "invalid GitHub repository in origin: $url"
    echo "$name"
}

check_source() {
    [[ "$(git_repo symbolic-ref --quiet --short HEAD)" == main ]] || die "--publish requires the main branch"
    [[ -z "$(git_repo status --porcelain)" ]] || die "working tree has uncommitted changes; commit them before --publish"
    [[ "$(git_repo rev-parse HEAD)" == "$release_commit" ]] || die "HEAD changed after release preparation started: expected $release_commit"
    [[ "$(project_version)" == "$release_version" ]] || die "MARKETING_VERSION changed after release preparation started: expected $release_version"
}

check_remote() {
    git_repo fetch origin main
    git_repo merge-base --is-ancestor refs/remotes/origin/main "$release_commit" \
        || die "origin/main has commits missing from $release_commit; integrate them before publishing"
}

check_tags() {
    local refs local_commit
    if git_repo show-ref --verify --quiet "refs/tags/$tag"; then
        local_commit="$(git_repo rev-parse "refs/tags/$tag^{commit}")"
        [[ "$local_commit" == "$release_commit" ]] || die "local tag $tag points to $local_commit, expected $release_commit"
    fi
    refs="$(git_repo ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}")" \
        || die "cannot read tag $tag from origin"
    remote_tag_commit="$(awk -v ref="refs/tags/$tag^{}" '$2 == ref { print $1 }' <<<"$refs")"
    if [[ -z "$remote_tag_commit" ]]; then
        remote_tag_commit="$(awk -v ref="refs/tags/$tag" '$2 == ref { print $1 }' <<<"$refs")"
    fi
    [[ -z "$remote_tag_commit" || "$remote_tag_commit" == "$release_commit" ]] \
        || die "remote tag $tag points to $remote_tag_commit, expected $release_commit"
}

check_release() {
    local state
    # A successful list distinguishes an absent release from authentication/network errors.
    state="$(gh api --paginate "repos/$repo/releases" --jq \
        ".[] | select(.tag_name == \"$tag\") | [.draft, .html_url, (.assets | length)] | @tsv")" \
        || die "cannot query GitHub releases for $repo"
    release_draft=""
    release_url=""
    release_asset_count=0
    if [[ -n "$state" ]]; then
        IFS=$'\t' read -r release_draft release_url release_asset_count <<<"$state"
        [[ "$release_draft" == true ]] || die "$tag is already published: $release_url; use a new version"
        [[ -n "$remote_tag_commit" ]] || die "draft $tag exists without a remote tag; cannot establish its source commit"
    fi
}

if $publish; then
    # origin is restricted to github.com; do not inherit an Enterprise API host.
    export GH_HOST=github.com
    command -v gh >/dev/null 2>&1 || die "--publish requires GitHub CLI (gh)"
    release_commit="$(git_repo rev-parse HEAD)"
    release_version="$(project_version)"
    [[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || die "expected one x.y.z MARKETING_VERSION in AppFinder.xcodeproj, got: $release_version"
    tag="v$release_version"
    check_source
    repo="$(github_repo "$(git_repo remote get-url origin)")"
    push_repo="$(github_repo "$(git_repo remote get-url --push origin)")"
    [[ "$repo" == "$push_repo" ]] || die "origin fetch repository $repo differs from push repository $push_repo"
    gh auth status --hostname github.com >/dev/null || die "GitHub CLI is not authenticated for github.com"
    permission="$(gh repo view "$repo" --json viewerPermission --jq .viewerPermission)" \
        || die "cannot read GitHub repository $repo"
    case "$permission" in
        ADMIN | MAINTAIN | WRITE) ;;
        *) die "GitHub permission for $repo is $permission; write access is required" ;;
    esac
    check_remote
    check_tags
    check_release
    archive="$RELEASE_DIR/$APP_NAME-$release_version.zip"
    checksum_file="$archive.sha256"
    if [[ -f "$commit_file" && "$(cat "$commit_file")" == "$release_commit" && -f "$archive" && -f "$checksum_file" ]]; then
        (cd "$RELEASE_DIR" && shasum -a 256 -c "$(basename "$checksum_file")") \
            || die "cached archive checksum failed: $archive"
        reuse_archive=true
        log "Reusing verified archive for $release_commit: $archive"
    elif [[ "$release_asset_count" -gt 0 ]]; then
        die "draft $tag already has assets but its verified local archive is missing; restore build/release before retrying"
    fi
fi

# Do not let notary settings inherited from the caller's environment stand in for
# the file (load_signing_env does the same for the signing identity).
unset APPFINDER_NOTARY_KEY APPFINDER_NOTARY_KEY_ID APPFINDER_NOTARY_ISSUER_FILE
load_signing_env

# --- Preflight: refuse before building anything. ---------------------------------

if [[ -z "$SIGN_IDENTITY" ]]; then
    die "no signing identity configured, refusing to build a release.
Set APPFINDER_CODESIGN_IDENTITY and APPFINDER_TEAM_ID in the signing env file
(currently $SIGN_ENV_FILE; APPFINDER_SIGNING_ENV overrides its path)."
fi

available_identities="$(security find-identity -v -p codesigning)"
if ! grep -qF -- "$SIGN_IDENTITY" <<<"$available_identities"; then
    die "the signing identity from $SIGN_ENV_FILE is not available in the keychain"
fi

NOTARY_ISSUER=""
if ! $skip_notarize; then
    missing=()
    [[ -n "${APPFINDER_NOTARY_KEY:-}" ]] || missing+=("APPFINDER_NOTARY_KEY")
    [[ -n "${APPFINDER_NOTARY_KEY_ID:-}" ]] || missing+=("APPFINDER_NOTARY_KEY_ID")
    [[ -n "${APPFINDER_NOTARY_ISSUER_FILE:-}" ]] || missing+=("APPFINDER_NOTARY_ISSUER_FILE")
    if ((${#missing[@]} > 0)); then
        die "notary settings are incomplete, missing: ${missing[*]}.
Set them in the signing env file (currently $SIGN_ENV_FILE; APPFINDER_SIGNING_ENV
overrides its path), or pass --skip-notarize to rehearse without notarizing."
    fi
    [[ -f "$APPFINDER_NOTARY_KEY" && -r "$APPFINDER_NOTARY_KEY" ]] \
        || die "APPFINDER_NOTARY_KEY does not name a readable file"
    [[ -f "$APPFINDER_NOTARY_ISSUER_FILE" && -r "$APPFINDER_NOTARY_ISSUER_FILE" ]] \
        || die "APPFINDER_NOTARY_ISSUER_FILE does not name a readable file"
    NOTARY_ISSUER="$(tr -d '[:space:]' <"$APPFINDER_NOTARY_ISSUER_FILE")"
    [[ -n "$NOTARY_ISSUER" ]] || die "the file named by APPFINDER_NOTARY_ISSUER_FILE is empty"
fi

# --- Helpers. --------------------------------------------------------------------

# Copies stdin to stderr with the issuer ID and the key path blanked out, so that
# notarytool diagnostics can be shown without leaking either.
redact() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//"$NOTARY_ISSUER"/<issuer>}"
        line="${line//"${APPFINDER_NOTARY_KEY:-}"/<key>}"
        printf '%s\n' "$line" >&2
    done
}

# notary <subcommand> [args...]: runs notarytool with the API key credentials.
notary() {
    local subcommand="$1"
    shift
    xcrun notarytool "$subcommand" "$@" \
        --key "$APPFINDER_NOTARY_KEY" \
        --key-id "$APPFINDER_NOTARY_KEY_ID" \
        --issuer "$NOTARY_ISSUER"
}

# check_app <app>: the app must be validly Developer ID signed with the hardened
# runtime and a secure timestamp, and must not carry get-task-allow (the notary
# service rejects all of these).
check_app() {
    local app="$1" details entitlements
    codesign --verify --strict --deep "$app" 2>&1 || die "signature verification failed for $app"

    details="$(codesign -dvv "$app" 2>&1)"
    grep -q '^Authority=Developer ID Application' <<<"$details" \
        || die "$app is not signed with a Developer ID Application certificate"
    grep -Eq '^CodeDirectory .*flags=[^ ]*\([^)]*runtime' <<<"$details" \
        || die "$app was signed without the hardened runtime"
    grep -q '^Timestamp=' <<<"$details" \
        || die "$app was signed without a secure timestamp"

    entitlements="$(codesign -d --entitlements - "$app" 2>&1)"
    if grep -q 'get-task-allow' <<<"$entitlements"; then
        die "$app carries the get-task-allow entitlement"
    fi
}

# notarize <app>: zips the app, submits it and waits for the verdict. On any
# verdict other than Accepted it prints the notary log and exits non-zero.
notarize() {
    local app="$1"
    local submit_zip="$RELEASE_DIR/$APP_NAME-notarize.zip"
    local result="$RELEASE_DIR/notary-submit.json"
    local errors="$RELEASE_DIR/notary-submit.err"
    local rc=0 status id

    ditto -c -k --keepParent "$app" "$submit_zip"

    log "Submitting to the notary service and waiting for the verdict (usually a few minutes)"
    notary submit "$submit_zip" --wait --timeout 30m --output-format json \
        >"$result" 2>"$errors" || rc=$?
    rm -f "$submit_zip"

    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
    id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
    [[ -s "$errors" ]] && redact <"$errors"
    [[ -z "$id" && -s "$result" ]] && redact <"$result"
    rm -f "$result" "$errors"

    if [[ "$status" == "Accepted" ]]; then
        log "Notarization accepted (submission $id)"
        return 0
    fi

    if [[ -n "$id" ]]; then
        log "Notarization verdict: ${status:-unknown} (submission $id). Notary log:"
        notary log "$id" 2>&1 | redact || true
        die "notarization did not succeed (status: ${status:-unknown})"
    fi
    die "notarytool submit failed before a verdict was returned (exit code $rc)"
}

# staple <app>: attaches the ticket. The CDN can lag a little behind the verdict,
# so retry for a short while.
staple() {
    local app="$1" attempt
    for attempt in 1 2 3 4 5 6; do
        if xcrun stapler staple "$app" >&2; then
            return 0
        fi
        if ((attempt < 6)); then
            log "Stapling failed (attempt $attempt of 6), retrying in 10 seconds"
            sleep 10
        fi
    done
    die "could not staple the notarization ticket to $app"
}

# --- Build. ----------------------------------------------------------------------

if ! $reuse_archive; then
    if $publish; then
        log "Running tests before publishing $tag"
        swift test --package-path "$APPFINDER_ROOT"
    fi
    rm -rf "$RELEASE_DIR"
    mkdir -p "$RELEASE_DIR"

    APPFINDER_NOTARIZABLE=1 "$SCRIPT_DIR/build.sh" release

    # Work on a copy: stapling modifies the bundle, and build/AppFinder.app stays as built.
    app="$RELEASE_DIR/$APP_NAME.app"
    ditto "$BUILD_DIR/$APP_NAME.app" "$app"

    log "Checking the signature"
    check_app "$app"

# --- Notarize and staple. --------------------------------------------------------

    if $skip_notarize; then
        log "Skipping notarization (--skip-notarize)"
    else
        notarize "$app"
        log "Stapling the ticket"
        staple "$app"
        codesign --verify --strict --deep "$app" || die "signature verification failed after stapling"
    fi

# --- Archive. --------------------------------------------------------------------

    version="$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")"
    [[ -n "$version" ]] || die "could not read the marketing version from $app"
    archive="$RELEASE_DIR/$APP_NAME-$version.zip"

    log "Creating ${archive#"$APPFINDER_ROOT"/}"
    ditto -c -k --keepParent "$app" "$archive"
fi

# --- Verify what would be distributed: the app as extracted from the archive. ----

verify_dir="$(mktemp -d "${TMPDIR:-/tmp}/appfinder-release-verify.XXXXXX")"
trap 'rm -rf "$verify_dir"' EXIT
ditto -x -k "$archive" "$verify_dir"
extracted="$verify_dir/$APP_NAME.app"
[[ -d "$extracted" ]] || die "the archive does not contain $APP_NAME.app"
if $publish; then
    archived_version="$(plutil -extract CFBundleShortVersionString raw -o - "$extracted/Contents/Info.plist")"
    [[ "$archived_version" == "$release_version" ]] \
        || die "archived version $archived_version differs from expected $release_version"
fi

log "Verifying the app extracted from the archive"
check_app "$extracted"

if ! $skip_notarize; then
    xcrun stapler validate "$extracted" >&2 || die "stapler validate failed for the archived app"

    assessment="$(spctl --assess --type execute -vv "$extracted" 2>&1)" \
        || die "Gatekeeper rejected the archived app: $assessment"
    grep -v '^origin=' <<<"$assessment" >&2 || true # the origin line names the certificate
    grep -q '^source=Notarized Developer ID' <<<"$assessment" \
        || die "Gatekeeper accepted the archived app, but not as Notarized Developer ID"
fi

# --- Report. ---------------------------------------------------------------------

sha256="$(shasum -a 256 "$archive")"
sha256="${sha256%% *}"
checksum_file="$archive.sha256"
printf '%s  %s\n' "$sha256" "$(basename "$archive")" >"$checksum_file"

if $skip_notarize; then
    log "WARNING: this archive is signed but NOT notarized or stapled, do not distribute it"
fi
echo "Archive: $archive"
echo "SHA-256: $sha256"
echo "Checksum file: $checksum_file"

# --- Publish. No remote mutations happen before the archived app passes verification. ---

if $publish; then
    check_source
    printf '%s\n' "$release_commit" >"$commit_file"
    check_remote
    check_tags
    check_release

    if [[ -z "$remote_tag_commit" ]]; then
        if ! git_repo show-ref --verify --quiet "refs/tags/$tag"; then
            git_repo tag -a "$tag" "$release_commit" -m "$APP_NAME $release_version"
        fi
        git_repo push --atomic origin "$release_commit:refs/heads/main" "refs/tags/$tag"
    else
        git_repo push origin "$release_commit:refs/heads/main"
    fi
    check_tags
    [[ "$remote_tag_commit" == "$release_commit" ]] || die "remote tag $tag is missing after push"

    if [[ -z "$release_draft" ]]; then
        notes_flags=(--generate-notes)
        if [[ -n "$notes_file" ]]; then
            notes_flags=(--notes-file "$notes_file")
        fi
        gh release create "$tag" --repo "$repo" --draft --verify-tag \
            --target "$release_commit" --title "$APP_NAME $release_version" "${notes_flags[@]}"
    fi

    assets="$(gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name')" \
        || die "cannot read assets for draft $tag"
    for asset in "$archive" "$checksum_file"; do
        check_release
        [[ "$release_draft" == true ]] || die "draft $tag disappeared before asset upload"
        name="$(basename "$asset")"
        if ! grep -Fxq -- "$name" <<<"$assets"; then
            gh release upload "$tag" "$asset" --repo "$repo"
        fi
        downloaded="$verify_dir/$name"
        gh release download "$tag" --repo "$repo" --pattern "$name" --output "$downloaded"
        cmp -s "$asset" "$downloaded" \
            || die "GitHub asset $name differs from $asset; refusing to overwrite or publish $tag"
    done
    check_source
    check_tags
    [[ "$remote_tag_commit" == "$release_commit" ]] || die "remote tag $tag disappeared before publication"
    # A concurrent publisher may have finished this release while assets were checked.
    check_release
    [[ "$release_draft" == true ]] || die "draft $tag disappeared before publication"
    gh release edit "$tag" --repo "$repo" --draft=false --verify-tag
    release_url="$(gh release view "$tag" --repo "$repo" --json url --jq .url)"
    echo "Release: $release_url"
fi
