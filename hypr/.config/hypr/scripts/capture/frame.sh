#!/usr/bin/env bash
# Frame a screenshot for sharing: a two-stop gradient backdrop in the active
# theme's accent colours, the theme's corner rounding, and a soft drop shadow.
# The framed copy is written beside the original and replaces the clipboard.
# It runs after a capture (`capture.sh screenshot <mode> --frame`), never on a
# keypress, so the extra ImageMagick process costs the keybind nothing.
set -euo pipefail

theme_file=${FRAME_THEME_FILE:-$HOME/.config/hypr/themes/.active/theme.json}
magick_command=${FRAME_MAGICK:-magick}
wl_copy_command=${FRAME_WL_COPY:-wl-copy}
padding=64
dry_run=0
input=

usage() {
  printf 'usage: %s [--dry-run] <image.png>\n' "${0##*/}"
}

fail() {
  printf 'frame: %s\n' "$1" >&2
  exit 1
}

for argument in "$@"; do
  case "$argument" in
    --dry-run) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) [[ -z "$input" ]] || { usage >&2; exit 2; }; input=$argument ;;
  esac
done
[[ -n "$input" ]] || { usage >&2; exit 2; }

[[ -f "$theme_file" ]] || fail "theme file not found: $theme_file (apply a theme with: theme set <slug>)"
theme=$(jq -r '.colors.accent // "", .colors.accentAlt // .colors.background // "", .style.rounding // 10' \
  "$theme_file" 2>/dev/null) || fail "could not read theme file: $theme_file"
{ read -r start_colour; read -r end_colour; read -r rounding; } <<<"$theme"
for colour in "$start_colour" "$end_colour"; do
  [[ "$colour" =~ ^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$ ]] ||
    fail "theme file has no usable accent colour ($colour): $theme_file"
done
[[ "$rounding" =~ ^[0-9]+$ ]] || fail "theme rounding is not a whole number ($rounding): $theme_file"

output="${input%.*}-framed.png"

# One ImageMagick pass. Percent escapes size the corner mask and the gradient
# from the image itself, so no separate identify call is needed.
magick_args=(
  "$input"
  '(' +clone -alpha extract -fill black -colorize 100 -fill white
      -draw "roundrectangle 0,0 %[fx:w-1],%[fx:h-1] $rounding,$rounding" ')'
  -alpha off -compose CopyOpacity -composite
  '(' +clone -background '#000000' -shadow 50x16+0+12 ')'
  +swap -background none -compose Over -layers merge +repage
  -bordercolor none -border "$padding"
  '(' +clone -alpha opaque -sparse-color Barycentric
      "0,0 $start_colour %[fx:w-1],%[fx:h-1] $end_colour" ')'
  +swap -compose Over -composite
  "$output"
)

if [[ "$dry_run" -eq 1 ]]; then
  printf '+'; printf ' %q' "$magick_command" "${magick_args[@]}"; printf '\n'
  printf '+ %q -t image/png < %q\n' "$wl_copy_command" "$output"
  exit 0
fi

[[ -f "$input" ]] || fail "image not found: $input"
command -v "$magick_command" >/dev/null 2>&1 ||
  fail "$magick_command is not installed (run: sudo pacman -S imagemagick)"
"$magick_command" "${magick_args[@]}" || fail "ImageMagick could not frame $input"
"$wl_copy_command" -t image/png <"$output" || fail "could not copy $output to the clipboard"
printf '%s\n' "$output"
