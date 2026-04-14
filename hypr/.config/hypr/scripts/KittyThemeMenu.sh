#!/usr/bin/env bash

set -euo pipefail

kitty_dir="$HOME/.config/kitty"
theme_dir="$kitty_dir/theme"
kitty_conf="$kitty_dir/kitty.conf"
current_theme_link="$theme_dir/current-theme.conf"
include_line="include $current_theme_link"
rofi_theme="$HOME/.config/rofi/config-wallpaper.rasi"

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

ensure_kitty_include() {
  mkdir -p "$kitty_dir"
  touch "$kitty_conf"

  local tmp
  tmp="$(mktemp)"

  grep -vxF "$include_line" "$kitty_conf" >"$tmp" || true

  printf '%s\n' "$include_line" >>"$tmp"
  mv "$tmp" "$kitty_conf"
}

current_theme_name() {
  if [ -L "$current_theme_link" ]; then
    local target
    target="$(readlink -f "$current_theme_link")"
    target="${target##*/}"
    printf '%s\n' "${target%.conf}"
  else
    printf 'unset'
  fi
}

pick_theme() {
  local theme_files=()
  local theme_names=()
  local theme_file

  while IFS= read -r theme_file; do
    local theme_name
    theme_name="${theme_file##*/}"
    theme_files+=("$theme_file")
    theme_names+=("${theme_name%.conf}")
  done < <(find "$theme_dir" -maxdepth 1 -type f -name '*.conf' ! -name 'current-theme.conf' | sort)

  if [ "${#theme_files[@]}" -eq 0 ]; then
    notify "Kitty Theme" "No theme files found in $theme_dir"
    exit 1
  fi

  if pgrep -x rofi >/dev/null 2>&1; then
    pkill rofi
  fi

  local rofi_cmd=(rofi -i -dmenu -p "Kitty Theme" -mesg "Current: $(current_theme_name)")
  if [ -f "$rofi_theme" ]; then
    rofi_cmd+=(-config "$rofi_theme")
  fi

  local selection
  selection="$(printf '%s\n' "${theme_names[@]}" | "${rofi_cmd[@]}")" || exit 0

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
    notify "Kitty Theme" "Theme selection was not recognized"
    exit 1
  fi

  theme_file="${theme_files[$index]}"

  ln -sfn "$theme_file" "$current_theme_link"
  ensure_kitty_include

  if kitty @ set-colors --all "$theme_file" >/dev/null 2>&1; then
    notify "Kitty Theme" "Applied $selection"
  else
    notify "Kitty Theme" "Saved $selection to kitty.conf. Restart kitty to apply it everywhere."
  fi
}

require_cmd find
require_cmd rofi
require_cmd ln
require_cmd readlink

pick_theme
