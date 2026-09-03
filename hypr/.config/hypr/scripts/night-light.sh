#!/usr/bin/env bash
# Toggle a compositor screen shader. Hyprsunset's CTM is accepted but not
# rendered on this system, while the legacy gamma protocol fails on both
# outputs, so neither color-control backend can provide a working night light.
set -euo pipefail

state_home=${XDG_STATE_HOME:-$HOME/.local/state}
state_file=${NIGHT_LIGHT_STATE_FILE:-$state_home/hyprland-desktop/night-light-shader}
hyprctl_command=${NIGHT_LIGHT_HYPRCTL:-hyprctl}
dry_run=0
action=toggle

usage() {
  printf 'usage: %s [--dry-run] [toggle|on|off|status]\n' "${0##*/}"
}

for argument in "$@"; do
  case "$argument" in
    --dry-run) dry_run=1 ;;
    toggle|on|off|status) action=$argument ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

is_enabled() {
  [[ -f "$state_file" ]]
}

reload_hyprland() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '+ %q reload\n' "$hyprctl_command"
  else
    "$hyprctl_command" reload >/dev/null
  fi
}

set_enabled() {
  local temporary_file

  if [[ "$dry_run" -eq 1 ]]; then
    printf '+ enable shader state: %s\n' "$state_file"
    reload_hyprland
    return
  fi

  mkdir -p -- "${state_file%/*}"
  temporary_file="${state_file}.tmp.$$"
  printf 'enabled\n' >"$temporary_file"
  mv -f -- "$temporary_file" "$state_file"
  reload_hyprland
  printf 'night-light: on (screen shader)\n'
}

set_disabled() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '+ disable shader state: %s\n' "$state_file"
    reload_hyprland
    return
  fi

  if [[ -e "$state_file" ]]; then
    rm -f -- "$state_file"
  fi
  reload_hyprland
  printf 'night-light: off\n'
}

case "$action" in
  status)
    if is_enabled; then
      printf 'night-light: on (screen shader)\n'
    else
      printf 'night-light: off\n'
    fi
    ;;
  on) set_enabled ;;
  off) set_disabled ;;
  toggle)
    if is_enabled; then
      set_disabled
    else
      set_enabled
    fi
    ;;
esac
