#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${TEXIUM_DIST_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE="${TEXIUM_APP_BUNDLE:-$DIST_DIR/TeXium.app}"
VERSION="1.0.0"
DMG="$DIST_DIR/TeXium-$VERSION.dmg"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Build the Release app before packaging the DMG." >&2
    exit 1
fi
ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$ACTUAL_VERSION" != "$VERSION" ]]; then
    echo "Expected TeXium $VERSION, found $ACTUAL_VERSION. Build the Release app again." >&2
    exit 1
fi
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/TeXium-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
/usr/bin/ditto --norsrc --noextattr "$APP_BUNDLE" "$STAGING_DIR/TeXium.app"
ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/codesign --verify --deep --strict "$STAGING_DIR/TeXium.app"
ARCHS="$(/usr/bin/lipo -archs "$STAGING_DIR/TeXium.app/Contents/MacOS/TeXium")"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
    echo "The Release app must contain both arm64 and x86_64 architectures." >&2
    exit 1
fi
/usr/bin/hdiutil create -volname "TeXium $VERSION" -srcfolder "$STAGING_DIR" -format UDZO -ov "$DMG"
if [[ -n "${TEXIUM_SIGNING_IDENTITY:-}" ]]; then
    /usr/bin/codesign --force --timestamp --sign "$TEXIUM_SIGNING_IDENTITY" "$DMG"
    /usr/bin/codesign --verify --verbose=2 "$DMG"
fi
/usr/bin/hdiutil verify "$DMG"
(cd "$DIST_DIR" && /usr/bin/shasum -a 256 "TeXium-$VERSION.dmg" > "TeXium-$VERSION.dmg.sha256")
echo "Created $DMG"
