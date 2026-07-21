#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="$HOME/.config/hypr"
PROFILE_DIR="$CONFIG_DIR/monitor_profiles"
MONITORS_FILE="$CONFIG_DIR/monitors.conf"
WORKSPACES_FILE="$CONFIG_DIR/workspaces.conf"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-profile-${HYPRLAND_INSTANCE_SIGNATURE:-default}"
FORCE=0

if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

has_monitor() {
  grep -Fxq "$1" <<<"$2"
}

pick_profile() {
  local monitors
  monitors="$(hyprctl -j monitors | jq -r '.[].name')"

  if has_monitor DP-5 "$monitors" && has_monitor DP-7 "$monitors" && has_monitor DP-9 "$monitors"; then
    printf '%s\n' kvm
  elif has_monitor DP-4 "$monitors" && has_monitor HDMI-A-3 "$monitors"; then
    printf '%s\n' desktop
  else
    printf '%s\n' laptop
  fi
}

workspace_monitor() {
  local profile="$1"
  local workspace="$2"

  case "$profile" in
    kvm)
      if (( workspace <= 5 )); then printf '%s\n' DP-5
      elif (( workspace <= 10 )); then printf '%s\n' DP-7
      else printf '%s\n' DP-9; fi
      ;;
    desktop)
      if (( workspace <= 5 )); then printf '%s\n' HDMI-A-3
      else printf '%s\n' DP-4; fi
      ;;
    laptop) printf '%s\n' eDP-1 ;;
  esac
}

move_existing_workspaces() {
  local profile="$1"
  local id monitor target

  while read -r id monitor; do
    target="$(workspace_monitor "$profile" "$id")"
    if [[ "$monitor" != "$target" ]]; then
      hyprctl dispatch moveworkspacetomonitor "$id" "$target"
    fi
  done < <(hyprctl -j workspaces | jq -r '.[] | select(.id >= 1 and .id <= 15) | "\(.id) \(.monitor)"')
}

apply_profile() {
  local profile
  profile="$(pick_profile)"

  if [[ "$FORCE" == 0 && -f "$STATE_FILE" && "$(<"$STATE_FILE")" == "$profile" ]]; then
    return
  fi

  cp "$PROFILE_DIR/$profile.monitors.conf" "$MONITORS_FILE"
  cp "$PROFILE_DIR/$profile.workspaces.conf" "$WORKSPACES_FILE"
  printf '%s\n' "$profile" >"$STATE_FILE"
  hyprctl reload
  move_existing_workspaces "$profile"
  if [[ "$profile" == desktop ]]; then
    hyprctl dispatch focusmonitor HDMI-A-3
  fi
  hyprctl notify -1 3000 "rgb(88c0d0)" "Loaded monitor profile: $profile"
}

apply_profile

if [[ "${1:-}" == "--watch" ]]; then
  while sleep 15; do
    apply_profile
  done
fi
