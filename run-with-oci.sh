#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${OCI_TRANSLATOR_CONFIG:-$ROOT_DIR/oci-translator.env}"

known_config_names=(
  APP_NAME
  GPT_MODEL
  INTERVAL
  OCR_ANCHOR
  OCR_DISPLAY
  OCR_LINES
  OCR_REGION
  OVERLAY_CLICK_THROUGH
  OVERLAY_FONT_SIZE
  OVERLAY_HEIGHT
  OVERLAY_WIDTH
  OVERLAY_X
  OVERLAY_Y
  OCI_GENAI_API_BASE_URL
  OCI_GENAI_API_KEY
  OCI_GENAI_API_MODE
  OCI_GENAI_API_URL
  OCI_MODEL_ID
  OCI_REGION
  SOURCE_LANG
  STABLE_AFTER
  TARGET_LANG
  USE_ACCESSIBILITY
  WINDOW_TITLE
)

environment_override_names=()
environment_override_values=()
for name in "${known_config_names[@]}"; do
  if [[ -n "${!name+x}" ]]; then
    environment_override_names+=("$name")
    environment_override_values+=("${!name}")
  fi
done

if [[ -f "$CONFIG_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  set +a
fi

for index in "${!environment_override_names[@]}"; do
  name="${environment_override_names[$index]}"
  export "$name=${environment_override_values[$index]}"
done

args=(
  --provider oci
  --target-lang "${TARGET_LANG:-KO}"
  --source-lang "${SOURCE_LANG:-EN}"
  --app-name "${APP_NAME:-Zoom}"
)

if [[ -n "${WINDOW_TITLE:-}" ]]; then
  args+=(--window-title "$WINDOW_TITLE")
fi

if [[ -n "${INTERVAL:-}" ]]; then
  args+=(--interval "$INTERVAL")
fi

if [[ -n "${STABLE_AFTER:-}" ]]; then
  args+=(--stable-after "$STABLE_AFTER")
fi

if [[ -n "${OCR_LINES:-}" ]]; then
  args+=(--ocr-lines "$OCR_LINES")
fi

if [[ -n "${OVERLAY_WIDTH:-}" ]]; then
  args+=(--overlay-width "$OVERLAY_WIDTH")
fi

if [[ -n "${OVERLAY_HEIGHT:-}" ]]; then
  args+=(--overlay-height "$OVERLAY_HEIGHT")
fi

if [[ -n "${OVERLAY_X:-}" ]]; then
  args+=(--overlay-x "$OVERLAY_X")
fi

if [[ -n "${OVERLAY_Y:-}" ]]; then
  args+=(--overlay-y "$OVERLAY_Y")
fi

if [[ -n "${OVERLAY_FONT_SIZE:-}" ]]; then
  args+=(--font-size "$OVERLAY_FONT_SIZE")
fi

if [[ "${OVERLAY_CLICK_THROUGH:-0}" == "1" ]]; then
  args+=(--overlay-click-through)
fi

if [[ "${USE_ACCESSIBILITY:-0}" != "1" ]]; then
  if [[ -n "${OCR_ANCHOR:-}" ]]; then
    args+=(--ocr-anchor "$OCR_ANCHOR")
  elif [[ -n "${OCR_REGION:-}" ]]; then
    args+=(--force-ocr --ocr-region "$OCR_REGION")
    if [[ -n "${OCR_DISPLAY:-}" ]]; then
      args+=(--ocr-display "$OCR_DISPLAY")
    fi
  else
    args+=(--select-ocr-region)
  fi
fi

"$ROOT_DIR/.build/release/zoomcc-translate-genai" "${args[@]}" "$@"
