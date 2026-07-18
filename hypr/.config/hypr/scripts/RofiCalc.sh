#!/usr/bin/env bash
# =============================================================================
# RofiCalc.sh — Calculator mode selector
# Super+Shift+C shows this menu; selecting a mode launches that calculator.
# =============================================================================
set -euo pipefail

ROFI_CONFIG="$HOME/.config/rofi/comet-glass.rasi"
SCRIPTS_DIR="$HOME/.config/hypr/scripts"

if ! command -v rofi >/dev/null 2>&1; then
    notify-send "Calculator" "rofi is not installed" 2>/dev/null || true
    exit 1
fi

choice="$(
    printf '󰇼  Scientific\n󰒗  Classic\n󰐘  Technical\n' |
    rofi -dmenu -i -p "Calculator" \
        -mesg "Select calculator mode" \
        -config "$ROFI_CONFIG"
)"

[[ -z "${choice:-}" ]] && exit 0

case "$choice" in
    *Scientific*) exec "$SCRIPTS_DIR/CalcScientific.sh" ;;
    *Classic*)    exec "$SCRIPTS_DIR/CalcClassic.sh" ;;
    *Technical*)  exec "$SCRIPTS_DIR/CalcTechnical.sh" ;;
esac
