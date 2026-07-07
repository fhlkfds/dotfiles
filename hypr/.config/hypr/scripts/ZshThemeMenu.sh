#!/usr/bin/env bash

set -euo pipefail

zsh_dir="${ZSH:-$HOME/.oh-my-zsh}"
themes_dir="$zsh_dir/themes"
custom_themes_dir="$zsh_dir/custom/themes"
current_theme_file="$HOME/.config/zsh/current-theme.zsh"
default_theme="powerlevel10k/powerlevel10k"
rofi_theme="$HOME/.config/rofi/current-theme.rasi"

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
  if [ -f "$current_theme_file" ]; then
    sed -n 's/^ZSH_THEME="\(.*\)"$/\1/p' "$current_theme_file"
  else
    printf '%s (default)\n' "$default_theme"
  fi
}

pick_theme() {
  local theme_names=()
  local theme_file

  # Stock oh-my-zsh themes
  while IFS= read -r theme_file; do
    local theme_name
    theme_name="${theme_file##*/}"
    theme_names+=("${theme_name%.zsh-theme}")
  done < <(find "$themes_dir/" -maxdepth 1 -type f -name '*.zsh-theme' | sort)

  # Custom themes: flat files and name/name.zsh-theme dirs (e.g. powerlevel10k)
  if [ -d "$custom_themes_dir" ]; then
    while IFS= read -r theme_file; do
      local theme_name
      theme_name="${theme_file##*/}"
      theme_names+=("${theme_name%.zsh-theme}")
    done < <(find "$custom_themes_dir/" -maxdepth 1 -type f -name '*.zsh-theme' | sort)

    local theme_subdir
    for theme_subdir in "$custom_themes_dir"/*/; do
      [ -d "$theme_subdir" ] || continue
      local dir_name
      dir_name="$(basename "$theme_subdir")"
      if [ -f "$theme_subdir/$dir_name.zsh-theme" ]; then
        theme_names+=("$dir_name/$dir_name")
      fi
    done
  fi

  if [ "${#theme_names[@]}" -eq 0 ]; then
    notify "Zsh Theme" "No theme files found in $themes_dir"
    exit 1
  fi

  if pgrep -x rofi >/dev/null 2>&1; then
    pkill rofi
  fi

  local rofi_cmd=(rofi -i -dmenu -p "Zsh Theme" -mesg "Current: $(current_theme_name)")
  if [ -f "$rofi_theme" ]; then
    rofi_cmd+=(-theme "$rofi_theme")
  fi

  local selection
  selection="$(printf '%s\n' "${theme_names[@]}" | "${rofi_cmd[@]}")" || exit 0

  if [ -z "$selection" ]; then
    exit 0
  fi

  local valid=false
  local name
  for name in "${theme_names[@]}"; do
    if [ "$name" = "$selection" ]; then
      valid=true
      break
    fi
  done

  if [ "$valid" != true ]; then
    notify "Zsh Theme" "Theme selection was not recognized"
    exit 1
  fi

  mkdir -p "${current_theme_file%/*}"
  printf 'ZSH_THEME="%s"\n' "$selection" >"$current_theme_file"

  # Stale p10k instant-prompt cache flashes the old prompt in new terminals
  if [ "$selection" != "$default_theme" ]; then
    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}"/p10k-instant-prompt-*
  fi

  notify "Zsh Theme" "Applied $selection. Open a new terminal to see it."
}

require_cmd find
require_cmd rofi
require_cmd sed

pick_theme
