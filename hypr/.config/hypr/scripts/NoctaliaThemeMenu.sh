#!/usr/bin/env bash

set -euo pipefail

shell_schemes_dir="/etc/xdg/quickshell/noctalia-shell/Assets/ColorScheme"
user_schemes_dir="$HOME/.config/noctalia/colorschemes"
settings_file="$HOME/.config/noctalia/settings.json"
rofi_theme="$HOME/.config/rofi/current-theme.rasi"
ipc=(qs -c noctalia-shell ipc call)

notify() {
  local title="$1"
  local message="$2"

  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$message"
  else
    printf '%s: %s\n' "$title" "$message" >&2
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf '%s not found\n' "$cmd" >&2
    exit 1
  fi
}

# Noctalia stores some schemes under file names that differ from display names
display_name() {
  case "$1" in
    "Noctalia-default") printf 'Noctalia (default)' ;;
    "Noctalia-legacy") printf 'Noctalia (legacy)' ;;
    "Tokyo-Night") printf 'Tokyo Night' ;;
    *) printf '%s' "$1" ;;
  esac
}

current_scheme() {
  jq -r '.colorSchemes.predefinedScheme // "unknown"' "$settings_file" 2>/dev/null || printf 'unknown'
}

pick_scheme() {
  local scheme_names=()
  local scheme_file

  while IFS= read -r scheme_file; do
    local scheme_name
    scheme_name="${scheme_file##*/}"
    scheme_names+=("$(display_name "${scheme_name%.json}")")
  done < <(find -L "$shell_schemes_dir/" "$user_schemes_dir/" -mindepth 2 -name '*.json' -type f 2>/dev/null | sort -u)

  if [ "${#scheme_names[@]}" -eq 0 ]; then
    notify "Noctalia Theme" "No color schemes found"
    exit 1
  fi

  if pgrep -x rofi >/dev/null 2>&1; then
    pkill rofi
  fi

  local rofi_cmd=(rofi -i -dmenu -p "Noctalia Theme" -mesg "Current: $(current_scheme)")
  if [ -f "$rofi_theme" ]; then
    rofi_cmd+=(-theme "$rofi_theme")
  fi

  local selection
  selection="$(printf '%s\n' "${scheme_names[@]}" | "${rofi_cmd[@]}")" || exit 0

  if [ -z "$selection" ]; then
    exit 0
  fi

  "${ipc[@]}" colorScheme set "$selection"
}

require_cmd find
require_cmd rofi
require_cmd jq
require_cmd qs

pick_scheme
