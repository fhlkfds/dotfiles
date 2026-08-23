#!/usr/bin/env bash
# =============================================================================
# capture/menu.sh — the Capture menu (Super+Ctrl+C)
#
# Follows the repo's rofi convention: current-theme.rasi with a comet-glass
# fallback, and a glob `case` mapping the visible label back to an action.
#
# The label is display metadata only -- it is never executed, interpolated into
# a command, or eval'd. Each branch calls a fixed argv.
# =============================================================================
set -euo pipefail

_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$_dir/common.sh"

require_cmd rofi || exit 1

if pgrep -x rofi >/dev/null 2>&1; then
  pkill rofi
fi

ROFI_THEME="$HOME/.config/rofi/current-theme.rasi"
[ -f "$ROFI_THEME" ] || ROFI_THEME="$HOME/.config/rofi/comet-glass.rasi"

REC_STATE=$("$_dir/record.sh" status)
if [ "$REC_STATE" = "recording" ]; then
  REC_LABEL="󰑊  Stop recording"
else
  REC_LABEL="󰑊  Screen recording…"
fi

ITEMS="󰆞  Screenshot — smart
󰩬  Screenshot — region
󰖯  Screenshot — window
󰍹  Screenshot — monitor
󰅍  Screenshot — copy only
󰉉  Screenshot — save only
$REC_LABEL
󰦥  Extract text (OCR)
󰸱  Colour picker"

CHOICE=$(printf '%s\n' "$ITEMS" | rofi -dmenu -i -p "Capture" \
  -mesg "Capture" -theme "$ROFI_THEME") || exit 0
[ -n "$CHOICE" ] || exit 0

case "$CHOICE" in
  *"smart")        exec "$_dir/screenshot.sh" smart ;;
  *"region")       exec "$_dir/screenshot.sh" region ;;
  *"window")       exec "$_dir/screenshot.sh" window ;;
  *"monitor")      exec "$_dir/screenshot.sh" monitor ;;
  *"copy only")    exec "$_dir/screenshot.sh" smart --copy ;;
  *"save only")    exec "$_dir/screenshot.sh" smart --save ;;
  *"Stop recording")    exec "$_dir/record.sh" stop ;;
  *"Screen recording"*) exec "$_dir/record.sh" menu ;;
  *"Extract text"*)     exec "$_dir/ocr.sh" region ;;
  *"Colour picker")     exec "$_dir/color.sh" ;;
esac
