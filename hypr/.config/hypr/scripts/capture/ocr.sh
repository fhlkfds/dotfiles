#!/usr/bin/env bash
# =============================================================================
# capture/ocr.sh — extract text from a screen region to the clipboard
#
# Usage: ocr.sh [region|smart|window|monitor] [--lang=eng+deu] [--psm=6]
#
# Preprocessing and the multi-PSM fallback ladder are adapted from the (dormant)
# Noctalia screen-toolkit ocr.sh: screen text is often light-on-dark, anti-
# aliased and small, and raw tesseract does poorly on it. Each pass is scored by
# how many non-whitespace characters it recovered, and the best one wins.
# =============================================================================
set -euo pipefail

_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=select.sh
source "$_dir/select.sh"

MODE="region"
LANGS="$OCR_LANGS"
PSM="$OCR_PSM"

for arg in "$@"; do
  case "$arg" in
    smart|region|window|monitor) MODE="$arg" ;;
    --lang=*) LANGS="${arg#--lang=}" ;;
    --psm=*)  PSM="${arg#--psm=}" ;;
    *) printf 'ocr.sh: unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

require_cmd grim || exit 1
require_cmd tesseract || exit 1
require_cmd wl-copy wl-clipboard || exit 1

WORK=$(mktemp -d) || { notify_error "Cannot create temp dir"; exit 1; }
cleanup_all() { capture_freeze_stop; rm -rf "$WORK"; }
trap cleanup_all EXIT INT TERM HUP

# --- languages ---------------------------------------------------------------
# Drop anything tesseract does not actually have installed, rather than letting
# it abort the whole run over one missing pack.
if AVAILABLE=$(tesseract --list-langs 2>/dev/null | tail -n +2); then
  VALID=""
  IFS='+' read -ra PARTS <<< "$LANGS"
  for l in "${PARTS[@]}"; do
    [ "$l" = "osd" ] && continue
    if printf '%s\n' "$AVAILABLE" | grep -qx "$l"; then
      VALID="${VALID}+${l}"
    fi
  done
  LANGS="${VALID#+}"

  # Falling back to "eng" is useless if eng is not one of the installed models
  # (the engine ships without any). Say so, rather than letting tesseract fail
  # with something cryptic.
  if [ -z "$LANGS" ]; then
    notify_error "No usable OCR language installed — run: sudo pacman -S tesseract-data-eng"
    exit 1
  fi
fi
[ -n "$LANGS" ] || LANGS="eng"

# --- select and capture ------------------------------------------------------
capture_freeze_start

TARGET=""
if ! TARGET=$(capture_select "$MODE"); then
  exit 0
fi

SHOT="$WORK/shot.png"
case "$TARGET" in
  region:*)  grim -g "${TARGET#region:}" "$SHOT" ;;
  monitor:*) grim -o "${TARGET#monitor:}" "$SHOT" ;;
  *) notify_error "Unrecognised capture target"; exit 1 ;;
esac || { notify_error "Capture failed"; exit 1; }

capture_freeze_stop

# --- preprocess --------------------------------------------------------------
PREP="$WORK/prep.pnm"
DENOISED="$WORK/denoised.pnm"

if has magick; then
  # Small regions are upscaled toward ~300px wide: tesseract needs the strokes.
  UPSCALE=()
  WIDTH=$(magick identify -format '%w' "$SHOT" 2>/dev/null || echo 0)
  if [ "$WIDTH" -gt 0 ] && [ "$WIDTH" -lt 200 ]; then
    FACTOR=$(awk "BEGIN{printf \"%.0f\", 300 / $WIDTH}")
    UPSCALE=(-scale "${FACTOR}00%")
  fi

  magick "$SHOT" "${UPSCALE[@]}" \
    -colorspace Gray -normalize -contrast-stretch 2%x1% -sharpen 0x1.5 +repage \
    "$PREP" 2>/dev/null || cp "$SHOT" "$PREP"

  # Light text on a dark panel confuses tesseract; invert when the region is
  # predominantly dark so it always sees dark-on-light.
  MEAN=$(magick "$PREP" -format '%[fx:mean]' info: 2>/dev/null || echo 1)
  if awk "BEGIN{exit !($MEAN < 0.4)}"; then
    magick "$PREP" -negate "$PREP" 2>/dev/null || true
  fi
  magick "$PREP" -median 1 "$DENOISED" 2>/dev/null || cp "$PREP" "$DENOISED"
else
  cp "$SHOT" "$PREP"
  cp "$SHOT" "$DENOISED"
fi

# --- recognise ---------------------------------------------------------------
run_ocr() {
  tesseract "$1" stdout \
    -l "$LANGS" --psm "$2" --oem "$OCR_OEM" --dpi "$OCR_DPI" \
    -c preserve_interword_spaces=1 2>/dev/null || true
}
count_chars() { printf '%s' "$1" | tr -d '[:space:]' | wc -c; }

BEST=$(run_ocr "$PREP" "$PSM")
BEST_LEN=$(count_chars "$BEST")

try_pass() {
  local text len
  text=$(run_ocr "$1" "$2")
  len=$(count_chars "$text")
  if [ "$len" -gt "$BEST_LEN" ]; then
    BEST_LEN=$len
    BEST=$text
  fi
}

# The configured PSM is tried first; the rest of the ladder only runs while the
# result still looks like a failure (fewer than 4 real characters).
if [ "$BEST_LEN" -lt 4 ] || [ "$PSM" != "6" ]; then
  try_pass "$DENOISED" 6
fi
if [ "$BEST_LEN" -lt 4 ]; then
  try_pass "$DENOISED" 4
fi
if [ "$BEST_LEN" -lt 4 ] && has magick; then
  THRESH="$WORK/thresh.pnm"
  if magick "$PREP" -threshold 85% "$THRESH" 2>/dev/null; then
    try_pass "$THRESH" 11
  fi
fi

# --- output ------------------------------------------------------------------
# Strip the trailing newline tesseract always appends, but keep interior blank
# lines -- they are real structure in the captured text.
TEXT="${BEST%$'\n'}"
TEXT="${TEXT%$'\n'}"

if [ -z "$(printf '%s' "$TEXT" | tr -d '[:space:]')" ]; then
  notify_error "No text found in selection"
  exit 1
fi

printf '%s' "$TEXT" | wl-copy

LINES=$(printf '%s\n' "$TEXT" | wc -l)
CHARS=$(printf '%s' "$TEXT" | wc -m)
notify "Text extracted" "${CHARS} characters, ${LINES} line(s) — copied to clipboard"
