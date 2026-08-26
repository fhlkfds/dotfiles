#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s save|restore\n' "${0##*/}"
}

die() {
  printf 'window-width: %s\n' "$1" >&2
  exit "${2:-1}"
}

hyprctl_command=${HYPR_WINDOW_WIDTH_HYPRCTL:-hyprctl}
state_dir=${HYPR_WINDOW_WIDTH_STATE_DIR:-${XDG_RUNTIME_DIR:-/tmp}}
state_file="$state_dir/hypr-window-width"

command -v "$hyprctl_command" >/dev/null 2>&1 || die "$hyprctl_command is not installed" 127
command -v jq >/dev/null 2>&1 || die "jq is not installed" 127

active_dimensions() {
  local active dimensions
  active=$("$hyprctl_command" -j activewindow) || die "could not query the active window"
  dimensions=$(jq -er '
    select(.address? != null and .address != "" and .address != "0x0")
    | select((.size? | type) == "array" and (.size | length) >= 2)
    | [.size[0], .size[1]]
    | select(all(.[]; type == "number" and . > 0 and floor == .))
    | @tsv
  ' <<< "$active") || die "no resizable active window"
  printf '%s\n' "$dimensions"
}

action=${1:-}
[[ $# -eq 1 ]] || { usage >&2; exit 2; }

case "$action" in
  save)
    read -r width _height <<< "$(active_dimensions)"
    [[ "$width" =~ ^[1-9][0-9]*$ ]] || die "active window width is invalid"
    mkdir -p -- "$state_dir"
    umask 077
    temp_file=$(mktemp "$state_file.XXXXXX")
    trap 'rm -f -- "${temp_file:-}"' EXIT
    printf '%s\n' "$width" > "$temp_file"
    mv -f -- "$temp_file" "$state_file"
    temp_file=""
    ;;
  restore)
    [[ -r "$state_file" ]] || die "no saved width; press Super+Alt+Home first"
    IFS= read -r saved_width < "$state_file" || die "saved width is empty"
    [[ "$saved_width" =~ ^[1-9][0-9]*$ ]] || die "saved width is invalid"
    read -r _width height <<< "$(active_dimensions)"
    "$hyprctl_command" dispatch \
      "hl.dsp.window.resize({ x = $saved_width, y = $height })" >/dev/null ||
      die "Hyprland rejected the saved width"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
