#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_NAME="TeXium"
BUNDLE_ID="app.texium.mac"
BUILD_DIR="${TEXIUM_BUILD_DIR:-${TMPDIR:-/tmp}/TeXium-Xcode}"
DIST_DIR="${TEXIUM_DIST_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
case "$MODE" in run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--build-only|build-only) ;; *) echo "usage: $0 [--verify|--build-only|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
# Ask AppKit to close normally so dirty buffers are saved. Never SIGKILL an editor.
if [[ "$MODE" != "--build-only" && "$MODE" != "build-only" ]] && pgrep -x "$APP_NAME" >/dev/null; then
    pkill -TERM -x "$APP_NAME"
    for _ in {1..30}; do
        if ! pgrep -x "$APP_NAME" >/dev/null; then break; fi
        sleep 0.2
    done
    if pgrep -x "$APP_NAME" >/dev/null; then
        echo "TeXium kept a window open to protect unsaved edits. Resolve its alert, then run again." >&2
        exit 1
    fi
fi
mkdir -p "$DIST_DIR" "$BUILD_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"
SIGNING_ARGS=("CODE_SIGN_IDENTITY=${TEXIUM_SIGNING_IDENTITY:--}" "CODE_SIGN_STYLE=Manual")
if [[ -n "${TEXIUM_DEVELOPMENT_TEAM:-}" ]]; then SIGNING_ARGS+=("DEVELOPMENT_TEAM=$TEXIUM_DEVELOPMENT_TEAM"); fi
xcodebuild -project TeXium.xcodeproj -scheme TeXium -configuration "${CONFIGURATION:-Debug}" -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" -clonedSourcePackagesDirPath "$ROOT_DIR/.build/SourcePackages" -packageCachePath "$ROOT_DIR/.build/SwiftPMCache" build "${SIGNING_ARGS[@]}"
STAGING_DIR="$(mktemp -d "$BUILD_DIR/package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
/usr/bin/ditto --norsrc --noextattr "$BUILD_DIR/Build/Products/${CONFIGURATION:-Debug}/$APP_NAME.app" "$STAGING_DIR/$APP_NAME.app"
/usr/bin/codesign --verify --deep --strict "$STAGING_DIR/$APP_NAME.app"
if [[ "${CONFIGURATION:-Debug}" == "Release" ]]; then
    /usr/bin/ditto -c -k --keepParent --norsrc --noextattr "$STAGING_DIR/$APP_NAME.app" "$DIST_DIR/TeXium-macOS.zip"
fi
# Replace the generated bundle instead of merging Debug dylibs into Release.
if [[ -e "$APP_BUNDLE" ]]; then mv "$APP_BUNDLE" "$STAGING_DIR/Previous.app"; fi
mv "$STAGING_DIR/$APP_NAME.app" "$APP_BUNDLE"
# File-provider metadata on Documents folders is not part of an app bundle.
/usr/bin/xattr -dr com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.ResourceFork "$APP_BUNDLE" 2>/dev/null || true
# Document providers can reattach Finder metadata immediately after a copy.
# Verify the delivered bytes through a clean local staging copy instead.
/usr/bin/ditto --norsrc --noextattr "$APP_BUNDLE" "$STAGING_DIR/Verified.app"
/usr/bin/codesign --verify --deep --strict "$STAGING_DIR/Verified.app"
case "$MODE" in
    --build-only|build-only) echo "Built $APP_BUNDLE" ;;
    --debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
    --logs|logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
    --telemetry|telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
    --verify|verify)
        # Track this launch, not any other TeXium process. AppKit restoration
        # can fail several seconds after open(1) has returned successfully.
        /usr/bin/open -n -W "$APP_BUNDLE" &
        LAUNCH_WAITER=$!
        for _ in {1..50}; do
            sleep 0.2
            if ! kill -0 "$LAUNCH_WAITER" 2>/dev/null; then
                wait "$LAUNCH_WAITER" || true
                echo "TeXium exited during the 10-second startup/restoration check." >&2
                exit 1
            fi
        done
        # Stop only open's waiter; leave the verified app running.
        kill "$LAUNCH_WAITER" 2>/dev/null || true
        wait "$LAUNCH_WAITER" 2>/dev/null || true
        echo "TeXium remained running through the 10-second startup/restoration check."
        ;;
    *) /usr/bin/open -n "$APP_BUNDLE" ;;
esac
