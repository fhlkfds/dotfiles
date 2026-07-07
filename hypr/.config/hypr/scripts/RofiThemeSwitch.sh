#!/usr/bin/env bash

set -euo pipefail

rofi_dir="$HOME/.config/rofi"
theme_dir="$rofi_dir/color-themes"
default_theme="$rofi_dir/comet-glass.rasi"
current_theme_link="$rofi_dir/current-theme.rasi"

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

current_theme_name() {
  if [ -L "$current_theme_link" ]; then
    local target
    target="$(readlink -f "$current_theme_link")"
    target="${target##*/}"
    printf '%s\n' "${target%.rasi}"
  else
    printf 'unset'
  fi
}

menu_theme() {
  if [ -e "$current_theme_link" ]; then
    printf '%s\n' "$current_theme_link"
  else
    printf '%s\n' "$default_theme"
  fi
}

pick_theme() {
  local theme_files=("$default_theme")
  local theme_names=("comet-glass")
  local theme_file

  while IFS= read -r theme_file; do
    local theme_name
    theme_name="${theme_file##*/}"
    theme_files+=("$theme_file")
    theme_names+=("${theme_name%.rasi}")
  done < <(find "$theme_dir/" -maxdepth 1 \( -type f -o -type l \) -name '*.rasi' | sort)

  if pgrep -x rofi >/dev/null 2>&1; then
    pkill rofi
  fi

  local selection
  selection="$(printf '%s\n' "${theme_names[@]}" |
    rofi -i -dmenu -p "Rofi Theme" -mesg "Current: $(current_theme_name)" -theme "$(menu_theme)")" || exit 0

  if [ -z "$selection" ]; then
    exit 0
  fi

  local index=-1
  local i
  for i in "${!theme_names[@]}"; do
    if [ "${theme_names[$i]}" = "$selection" ]; then
      index="$i"
      break
    fi
  done

  if [ "$index" -lt 0 ]; then
    notify "Rofi Theme" "Theme selection was not recognized"
    exit 1
  fi

  ln -sfn "${theme_files[$index]}" "$current_theme_link"
  notify "Rofi Theme" "Applied $selection"
}

require_cmd find
require_cmd rofi
require_cmd ln
require_cmd readlink

pick_theme
