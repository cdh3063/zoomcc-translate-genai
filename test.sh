#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
SWIFTC="${SWIFTC:-swiftc}"

"$ROOT_DIR/build.sh" >/dev/null

"$SWIFTC" \
  -module-cache-path "$BUILD_DIR/module-cache" \
  -I "$BUILD_DIR/manual" \
  "$ROOT_DIR/Scripts/core-smoke-test.swift" \
  "$BUILD_DIR/manual/CaptionStabilizer.o" \
  -o "$BUILD_DIR/manual/core-smoke-test"

"$BUILD_DIR/manual/core-smoke-test"

"$SWIFTC" \
  -D OVERLAY_SMOKE_TEST \
  -module-cache-path "$BUILD_DIR/module-cache" \
  -I "$BUILD_DIR/manual" \
  "$ROOT_DIR/Sources/ZoomCaptionTranslator/main.swift" \
  "$ROOT_DIR/Scripts/overlay-smoke-test.swift" \
  "$BUILD_DIR/manual/CaptionStabilizer.o" \
  -o "$BUILD_DIR/manual/overlay-smoke-test"

"$BUILD_DIR/manual/overlay-smoke-test" "$BUILD_DIR/manual"
python3 "$ROOT_DIR/Scripts/translation-smoke-test.py"
