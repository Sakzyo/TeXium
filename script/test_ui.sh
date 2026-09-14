#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"
RESULT_PATH="$ROOT_DIR/.build/UI-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project TeXium.xcodeproj -scheme TeXium -destination 'platform=macOS' -derivedDataPath "${TMPDIR:-/tmp}/TeXium-UITests" -resultBundlePath "$RESULT_PATH" -packageCachePath "$ROOT_DIR/.build/SwiftPMCache" "${TEST_ACTION:-test}" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual TEXIUM_APP_BUNDLE_IDENTIFIER=app.texium.verification "$@"
