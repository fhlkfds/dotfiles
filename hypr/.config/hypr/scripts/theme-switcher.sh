#!/usr/bin/env bash
# theme-switcher.sh — Select and apply a Hyprland theme via Rofi
#
# Bound to: SUPER + T
# Lists available themes from themes.json, displays in a Rofi menu,
# and applies the selected theme across all config components.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$(dirname "$SCRIPT_DIR")/themes"
THEMES_JSON="$THEMES_DIR/themes.json"
APPLY_SCRIPT="$THEMES_DIR/apply.sh"
STATE_FILE="$THEMES_DIR/current-theme"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
ROFI_THEME="$CONFIG_HOME/rofi/current-theme.rasi"
ROFI_DEFAULT="$CONFIG_HOME/rofi/comet-glass.rasi"

notify() {
  local title="$1" message="$2"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$message"
  else
    printf '%s: %s\n' "$title" "$message" >&2
  fi
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Required command not found: $1"
  fi
}

require_cmd jq
require_cmd rofi

# ── Get current theme ───────────────────────────────────────────────────────
current_theme() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  else
    printf 'None'
  fi
}

# ── Build theme list with display names ─────────────────────────────────────
# We read the "display" field for the menu label and use the raw key as the value
build_menu() {
  jq -r '.themes | to_entries[] | "\(.value.display)  (\(.key))"' "$THEMES_JSON"
}

# ── Validate and apply ──────────────────────────────────────────────────────
apply_theme() {
  local selection="$1"

  # Extract the actual theme name from the display format:
  # "Catppuccin Mocha 🟣  (Catppuccin Mocha)" -> "Catppuccin Mocha"
  local theme_name
  theme_name=$(printf '%s' "$selection" | sed -n 's/.*(\(.*\))/\1/p')

  if [ -z "$theme_name" ]; then
    notify "Theme Switcher" "Could not parse selection"
    exit 1
  fi

  if [ ! -x "$APPLY_SCRIPT" ]; then
    die "Apply script not found or not executable: $APPLY_SCRIPT"
  fi

  "$APPLY_SCRIPT" "$theme_name"
}

# ── Main ────────────────────────────────────────────────────────────────────
if pgrep -x rofi >/dev/null 2>&1; then
  pkill rofi 2>/dev/null || true
  sleep 0.1
fi

CURRENT=$(current_theme)

# Build the rofi command with the right theme
rofi_cmd=(rofi -i -dmenu -p "Theme Switcher" -mesg "Current: $CURRENT")
if [ -f "$ROFI_THEME" ]; then
  rofi_cmd+=(-theme "$ROFI_THEME")
elif [ -f "$ROFI_DEFAULT" ]; then
  rofi_cmd+=(-theme "$ROFI_DEFAULT")
fi

SELECTION=$(build_menu | "${rofi_cmd[@]}") || exit 0

if [ -z "$SELECTION" ]; then
  exit 0
fi

apply_theme "$SELECTION"