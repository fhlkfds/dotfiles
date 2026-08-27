#!/usr/bin/env bash
# Keep the Hyprland keybinding usable even when the independent modes Stow
# package has not been deployed. Prefer desktop-mode when it is available so
# Quickshell and the keybinding continue to share one state controller.
set -euo pipefail

warm_temperature=${NIGHT_LIGHT_WARM_TEMPERATURE:-1000}
normal_temperature=${NIGHT_LIGHT_NORMAL_TEMPERATURE:-6500}
desktop_mode=${NIGHT_LIGHT_DESKTOP_MODE:-$HOME/.local/bin/desktop-mode}
hyprctl_command=${NIGHT_LIGHT_HYPRCTL:-hyprctl}
hyprsunset_command=${NIGHT_LIGHT_HYPRSUNSET:-hyprsunset}
pgrep_command=${NIGHT_LIGHT_PGREP:-pgrep}
setsid_command=${NIGHT_LIGHT_SETSID:-setsid}
startup_attempts=${NIGHT_LIGHT_STARTUP_ATTEMPTS:-20}
startup_delay=${NIGHT_LIGHT_STARTUP_DELAY:-0.1}
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

if [[ "$dry_run" -eq 0 && "${NIGHT_LIGHT_FORCE_DIRECT:-0}" != 1 && -x "$desktop_mode" ]]; then
  case "$action" in
    toggle) exec "$desktop_mode" toggle night-light ;;
    on) exec "$desktop_mode" enable night-light ;;
    off) exec "$desktop_mode" disable night-light ;;
    status) exec "$desktop_mode" status night-light ;;
  esac
fi

require_command() {
  command -v -- "$1" >/dev/null 2>&1 || {
    printf 'night-light: required command is unavailable: %s\n' "$1" >&2
    exit 127
  }
}

is_running() {
  "$pgrep_command" -x hyprsunset >/dev/null 2>&1
}

current_temperature() {
  local output
  output=$("$hyprctl_command" hyprsunset temperature 2>/dev/null) || return 1
  awk 'match($0, /[0-9]+/) { print substr($0, RSTART, RLENGTH); exit }' <<<"$output"
}

start_backend() {
  local attempt

  is_running && return 0
  if [[ "$dry_run" -eq 1 ]]; then
    printf '+ %q -f %q\n' "$setsid_command" "$hyprsunset_command"
    return 0
  fi

  require_command "$setsid_command"
  require_command "$hyprsunset_command"
  "$setsid_command" -f "$hyprsunset_command"
  for ((attempt = 0; attempt < startup_attempts; attempt++)); do
    is_running && return 0
    sleep "$startup_delay"
  done
  printf 'night-light: Hyprsunset did not become ready\n' >&2
  return 1
}

set_temperature() {
  local temperature=$1

  if [[ "$dry_run" -eq 1 ]]; then
    printf '+ %q hyprsunset temperature %q\n' "$hyprctl_command" "$temperature"
    return 0
  fi
  "$hyprctl_command" hyprsunset temperature "$temperature" >/dev/null
  printf 'night-light: temperature set to %s K\n' "$temperature"
}

require_command "$hyprctl_command"
require_command "$pgrep_command"

case "$action" in
  status)
    if is_running && [[ "$(current_temperature || true)" == "$warm_temperature" ]]; then
      printf 'night-light: on (%s K)\n' "$warm_temperature"
    else
      printf 'night-light: off (%s K)\n' "$normal_temperature"
    fi
    ;;
  on)
    start_backend
    set_temperature "$warm_temperature"
    ;;
  off)
    if is_running; then
      set_temperature "$normal_temperature"
    else
      printf 'night-light: already off\n'
    fi
    ;;
  toggle)
    if is_running && [[ "$(current_temperature || true)" == "$warm_temperature" ]]; then
      set_temperature "$normal_temperature"
    else
      start_backend
      set_temperature "$warm_temperature"
    fi
    ;;
esac
