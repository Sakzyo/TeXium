#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="1.0.0"
IDENTITY="${TEXIUM_SIGNING_IDENTITY:-}"
TEAM_ID="${TEXIUM_DEVELOPMENT_TEAM:-}"
NOTARY_PROFILE="${TEXIUM_NOTARY_PROFILE:-TeXiumNotary}"
PUBLISH=false
if [[ "${1:-}" == "--publish" ]]; then PUBLISH=true
elif [[ -n "${1:-}" ]]; then echo "usage: $0 [--publish]" >&2; exit 2
fi

if [[ -z "$IDENTITY" || -z "$TEAM_ID" ]]; then
    echo "Set TEXIUM_SIGNING_IDENTITY to the full Developer ID Application identity and TEXIUM_DEVELOPMENT_TEAM to its Team ID." >&2
    exit 1
fi
if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$IDENTITY\""; then
    echo "The Developer ID Application identity is not installed with its private key: $IDENTITY" >&2
    exit 1
fi
if ! /usr/bin/xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "The notarytool Keychain profile '$NOTARY_PROFILE' is missing or invalid." >&2
    echo "Create it interactively with: xcrun notarytool store-credentials '$NOTARY_PROFILE'" >&2
    exit 1
fi
if [[ -n "$(/usr/bin/git -C "$ROOT_DIR" status --porcelain)" ]]; then
    echo "Commit or stash repository changes before producing a release." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/TeXium-release.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
BUILD_DIR="$WORK_DIR/Xcode"
ARTIFACT_DIR="$WORK_DIR/artifacts"
mkdir -p "$ARTIFACT_DIR"

CONFIGURATION=Release \
TEXIUM_BUILD_DIR="$BUILD_DIR" \
TEXIUM_DIST_DIR="$ARTIFACT_DIR" \
TEXIUM_SIGNING_IDENTITY="$IDENTITY" \
TEXIUM_DEVELOPMENT_TEAM="$TEAM_ID" \
"$ROOT_DIR/script/build_and_run.sh" --build-only

APP="$ARTIFACT_DIR/TeXium.app"
APP_ZIP="$ARTIFACT_DIR/TeXium-$VERSION-notary.zip"
APP_INFO="$WORK_DIR/app-signature.txt"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/codesign -d --verbose=4 "$APP" 2> "$APP_INFO"
/usr/bin/grep -Fq "Authority=Developer ID Application:" "$APP_INFO"
/usr/bin/grep -Fq "TeamIdentifier=$TEAM_ID" "$APP_INFO"
/usr/bin/grep -Eq '^flags=.*runtime' "$APP_INFO"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr "$APP" "$APP_ZIP"

submit_and_require_acceptance() {
    local artifact="$1"
    local result="$2"
    local label
    label="$(basename "$artifact")"
    if ! /usr/bin/xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$result"; then
        mkdir -p "$ROOT_DIR/dist/notary-failure"
        /usr/bin/ditto "$result" "$ROOT_DIR/dist/notary-failure/$label.json"
        echo "Notarization submission failed. See $ROOT_DIR/dist/notary-failure/$label.json" >&2
        exit 1
    fi
    local status
    status="$(/usr/bin/plutil -extract status raw -o - "$result")"
    if [[ "$status" != "Accepted" ]]; then
        local submission_id
        submission_id="$(/usr/bin/plutil -extract id raw -o - "$result")"
        /usr/bin/xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" "$result.log" || true
        mkdir -p "$ROOT_DIR/dist/notary-failure"
        /usr/bin/ditto "$result" "$ROOT_DIR/dist/notary-failure/$label.json"
        if [[ -f "$result.log" ]]; then /usr/bin/ditto "$result.log" "$ROOT_DIR/dist/notary-failure/$label.log"; fi
        echo "Notarization was not accepted. See $ROOT_DIR/dist/notary-failure/" >&2
        exit 1
    fi
}

submit_and_require_acceptance "$APP_ZIP" "$WORK_DIR/app-notary.json"
/usr/bin/xcrun stapler staple "$APP"
/usr/bin/xcrun stapler validate "$APP"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP"

TEXIUM_DIST_DIR="$ARTIFACT_DIR" \
TEXIUM_APP_BUNDLE="$APP" \
TEXIUM_SIGNING_IDENTITY="$IDENTITY" \
"$ROOT_DIR/script/package_dmg.sh"
DMG="$ARTIFACT_DIR/TeXium-$VERSION.dmg"
submit_and_require_acceptance "$DMG" "$WORK_DIR/dmg-notary.json"
/usr/bin/xcrun stapler staple "$DMG"
/usr/bin/xcrun stapler validate "$DMG"
/usr/bin/codesign --verify --verbose=2 "$DMG"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
(cd "$ARTIFACT_DIR" && /usr/bin/shasum -a 256 "TeXium-$VERSION.dmg" > "TeXium-$VERSION.dmg.sha256")

mkdir -p "$ROOT_DIR/dist"
/usr/bin/ditto "$DMG" "$ROOT_DIR/dist/TeXium-$VERSION.dmg"
/usr/bin/ditto "$ARTIFACT_DIR/TeXium-$VERSION.dmg.sha256" "$ROOT_DIR/dist/TeXium-$VERSION.dmg.sha256"

if $PUBLISH; then
    GH="${TEXIUM_GH:-$(command -v gh || true)}"
    if [[ -z "$GH" ]]; then echo "Install or configure GitHub CLI before publishing." >&2; exit 1; fi
    if [[ "$($GH release view "v$VERSION" --repo Sakzyo/TeXium --json isDraft --jq .isDraft)" != "true" ]]; then
        echo "The v$VERSION release is missing or is no longer a draft." >&2
        exit 1
    fi
    HEAD="$(/usr/bin/git -C "$ROOT_DIR" rev-parse HEAD)"
    "$GH" release edit "v$VERSION" --repo Sakzyo/TeXium --target "$HEAD" --notes-file "$ROOT_DIR/docs/releases/1.0.0.md"
    "$GH" release upload "v$VERSION" "$ROOT_DIR/dist/TeXium-$VERSION.dmg" "$ROOT_DIR/dist/TeXium-$VERSION.dmg.sha256" --clobber --repo Sakzyo/TeXium
    EXPECTED_DIGEST="sha256:$(/usr/bin/shasum -a 256 "$ROOT_DIR/dist/TeXium-$VERSION.dmg" | /usr/bin/awk '{print $1}')"
    REMOTE_DIGEST="$($GH release view "v$VERSION" --repo Sakzyo/TeXium --json assets --jq ".assets[] | select(.name == \"TeXium-$VERSION.dmg\") | .digest")"
    if [[ "$REMOTE_DIGEST" != "$EXPECTED_DIGEST" ]]; then
        echo "The uploaded DMG digest does not match the notarized local artifact." >&2
        exit 1
    fi
    "$GH" release edit "v$VERSION" --draft=false --latest --repo Sakzyo/TeXium
fi
echo "Developer ID signed and notarized TeXium $VERSION: $ROOT_DIR/dist/TeXium-$VERSION.dmg"
