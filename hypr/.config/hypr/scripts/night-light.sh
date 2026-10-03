#!/usr/bin/env bash
# Toggle a compositor screen shader. Hyprsunset's CTM is accepted but not
# rendered on this system, while the legacy gamma protocol fails on both
# outputs, so neither color-control backend can provide a working night light.
set -euo pipefail

state_home=${XDG_STATE_HOME:-$HOME/.local/state}
state_file=${NIGHT_LIGHT_STATE_FILE:-$state_home/hyprland-desktop/night-light-shader}
hyprctl_command=${NIGHT_LIGHT_HYPRCTL:-hyprctl}
shader=$HOME/.config/hypr/shaders/night-light.frag
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

# Apply the shader live. `hyprctl reload` re-parses the whole Lua config on the
# compositor thread (about a second of frozen screen) and resets runtime
# toggles such as gaps and zoom; a runtime hl.config() of screen_shader makes
# Hyprland recompile just the shader. hyprland.lua reads the state file at login.
#
# A screen_shader refresh damages each monitor, but does not force repeated
# full frames. Re-setting border_size to its current value triggers Hyprland's
# window-state refresh, requesting two full frames and scheduling each monitor
# without changing the configured border width (issue #115).
apply_shader() {
  local expression response delimiter='=='
  # A HOME path can contain the closing delimiter of a Lua long string.
  while [[ "$1" == *"]$delimiter]"* ]]; do
    delimiter+='='
  done
  expression="hl.config({ decoration = { screen_shader = [${delimiter}[$1]${delimiter}] }, general = { border_size = assert(hl.get_config(\"general.border_size\")) } })"
  if [[ "$dry_run" -eq 1 ]]; then
    printf '+ %q eval %q\n' "$hyprctl_command" "$expression"
  else
    if ! response=$("$hyprctl_command" eval "$expression" 2>&1) || [[ "$response" != ok ]]; then
      printf 'night-light: could not apply shader: %s\n' "${response:-hyprctl returned no response}" >&2
      return 1
    fi
  fi
}

set_enabled() {
  local temporary_file

  if [[ "$dry_run" -eq 1 ]]; then
    printf '+ enable shader state: %s\n' "$state_file"
    apply_shader "$shader"
    return
  fi

  mkdir -p -- "${state_file%/*}"
  temporary_file="${state_file}.tmp.$$"
  printf 'enabled\n' >"$temporary_file"
  mv -f -- "$temporary_file" "$state_file"
  apply_shader "$shader"
  printf 'night-light: on (screen shader)\n'
}

set_disabled() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '+ disable shader state: %s\n' "$state_file"
    apply_shader ""
    return
  fi

  if [[ -e "$state_file" ]]; then
    rm -f -- "$state_file"
  fi
  apply_shader ""
  printf 'night-light: off\n'
}

# Serialize the state decision and IPC together: overlapping toggles otherwise
# can apply their shaders in the opposite order to their state-file updates.
# Keep desired state on IPC failure so hyprland.lua can apply it at next login.
if [[ "$action" != status && "$dry_run" -eq 0 ]]; then
  mkdir -p -- "${state_file%/*}"
  exec {state_lock}>"${state_file}.lock"
  flock -x "$state_lock"
fi

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
