#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
SWIFTC="${SWIFTC:-swiftc}"

mkdir -p "$BUILD_DIR/manual" "$BUILD_DIR/release" "$BUILD_DIR/module-cache"

"$SWIFTC" \
  -module-cache-path "$BUILD_DIR/module-cache" \
  -parse-as-library \
  -emit-module \
  -emit-object \
  -module-name ZoomCaptionCore \
  "$ROOT_DIR/Sources/ZoomCaptionCore/CaptionStabilizer.swift" \
  -emit-module-path "$BUILD_DIR/manual/ZoomCaptionCore.swiftmodule" \
  -o "$BUILD_DIR/manual/CaptionStabilizer.o"

"$SWIFTC" \
  -module-cache-path "$BUILD_DIR/module-cache" \
  -I "$BUILD_DIR/manual" \
  "$ROOT_DIR/Sources/ZoomCaptionTranslator/main.swift" \
  "$BUILD_DIR/manual/CaptionStabilizer.o" \
  -o "$BUILD_DIR/release/zoom-caption-translator"

echo "$BUILD_DIR/release/zoom-caption-translator"
