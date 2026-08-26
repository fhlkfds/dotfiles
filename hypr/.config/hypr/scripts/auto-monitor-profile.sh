#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${HYPR_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr}"
PROFILE_DIR="${HYPR_PROFILE_DIR:-$CONFIG_DIR/monitor_profiles}"
MONITORS_FILE="$CONFIG_DIR/monitors.lua"
WORKSPACES_FILE="$CONFIG_DIR/workspaces.lua"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-profile-${HYPRLAND_INSTANCE_SIGNATURE:-default}"
HYPRCTL="${HYPRCTL:-hyprctl}"
FORCE=0
DRY_RUN=0
WATCH=0

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --watch) WATCH=1 ;;
    *) printf 'usage: %s [--force] [--dry-run] [--watch]\n' "$(basename "$0")" >&2; exit 2 ;;
  esac
done

has_monitor() {
  grep -Fxq "$1" <<<"$2"
}

pick_profile() {
  local monitors
  monitors="$("$HYPRCTL" -j monitors | jq -r '.[].name')"

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
      "$HYPRCTL" dispatch "hl.dsp.workspace.move({ workspace = $id, monitor = \"$target\" })"
    fi
  done < <("$HYPRCTL" -j workspaces | jq -r '.[] | select(.id >= 1 and .id <= 15) | "\(.id) \(.monitor)"')
}

apply_profile() {
  local profile
  profile="$(pick_profile)"

  if [[ "$FORCE" == 0 && -f "$STATE_FILE" && "$(<"$STATE_FILE")" == "$profile" ]]; then
    return
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    printf 'profile=%s\nmonitors=%s\nworkspaces=%s\n' \
      "$profile" "$PROFILE_DIR/$profile.monitors.lua" "$PROFILE_DIR/$profile.workspaces.lua"
    return
  fi

  cp "$PROFILE_DIR/$profile.monitors.lua" "$MONITORS_FILE"
  cp "$PROFILE_DIR/$profile.workspaces.lua" "$WORKSPACES_FILE"
  printf '%s\n' "$profile" >"$STATE_FILE"
  "$HYPRCTL" reload
  move_existing_workspaces "$profile"
  if [[ "$profile" == desktop ]]; then
    "$HYPRCTL" dispatch 'hl.dsp.focus({ monitor = "HDMI-A-3" })'
  fi
  "$HYPRCTL" notify -1 3000 "rgb(88c0d0)" "Loaded monitor profile: $profile"
}

apply_profile

if [[ "$WATCH" == 1 && "$DRY_RUN" == 0 ]]; then
  while sleep 15; do
    apply_profile
  done
fi
