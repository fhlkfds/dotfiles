#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${HYPR_DIR:-$(dirname "$SCRIPT_DIR")}"
PROFILE_DIR="${HYPR_PROFILE_DIR:-$CONFIG_DIR/monitor_profiles}"
APPLIER="${MONITOR_PROFILE_APPLIER:-$SCRIPT_DIR/auto-monitor-profile.sh}"
HYPRCTL="${HYPRCTL:-hyprctl}"
ROFI_THEME="${MONITOR_PROFILE_ROFI_THEME:-$HOME/.config/rofi/current-theme.rasi}"
[[ -r "$ROFI_THEME" ]] || ROFI_THEME="$HOME/.config/rofi/comet-glass.rasi"

DRY_RUN=0
NEXT=0
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --next) NEXT=1 ;;
    *)
      printf 'usage: %s [--next] [--dry-run]\n' "$(basename "$0")" >&2
      exit 2
      ;;
  esac
  shift
done
((DRY_RUN == 0 || NEXT == 1)) || NEXT=1

notify_error() {
  if command -v "$HYPRCTL" >/dev/null 2>&1; then
    "$HYPRCTL" notify -1 5000 "rgb(bf616a)" "$1" >/dev/null 2>&1 || true
  fi
  printf '%s\n' "$1" >&2
}

shopt -s nullglob
profiles=()
for monitors in "$PROFILE_DIR"/*.monitors.lua; do
  profile="${monitors##*/}"
  profile="${profile%.monitors.lua}"
  [[ "$profile" =~ ^[a-zA-Z0-9_-]+$ ]] || continue
  [[ -r "$PROFILE_DIR/$profile.workspaces.lua" ]] && profiles+=("$profile")
done
((${#profiles[@]} > 0)) || { notify_error 'No paired monitor profiles found'; exit 1; }

active_profile=""
for profile in "${profiles[@]}"; do
  if cmp -s "$CONFIG_DIR/monitors.lua" "$PROFILE_DIR/$profile.monitors.lua" &&
     cmp -s "$CONFIG_DIR/workspaces.lua" "$PROFILE_DIR/$profile.workspaces.lua"; then
    active_profile="$profile"
    break
  fi
done

next_profile() {
  local cycle=(desktop laptop work presentation) index
  for index in "${!cycle[@]}"; do
    if [[ "${cycle[$index]}" == "$active_profile" ]]; then
      printf '%s\n' "${cycle[$(((index + 1) % ${#cycle[@]}))]}"
      return
    fi
  done
  printf '%s\n' desktop
}

apply_profile() {
  local profile="$1" simulated
  if ((DRY_RUN)); then
    if [[ -n "${SIMULATED_MONITORS:-}" ]]; then
      simulated="$SIMULATED_MONITORS"
    elif [[ ! -t 0 ]]; then
      simulated="$(</dev/stdin)"
    else
      notify_error 'Dry-run requires monitor JSON in $SIMULATED_MONITORS or stdin'
      return 1
    fi
    [[ -n "$simulated" ]] || { notify_error 'Simulated monitor list is empty'; return 1; }
    SIMULATED_MONITORS="$simulated" "$APPLIER" --profile "$profile" --force --dry-run
  else
    "$APPLIER" --profile "$profile" --force
  fi
}

if ((NEXT)); then
  apply_profile "$(next_profile)"
  exit $?
fi

command -v rofi >/dev/null 2>&1 || { notify_error 'rofi is not installed'; exit 1; }
menu='↻ Next profile'
for profile in "${profiles[@]}"; do
  if [[ "$profile" == "$active_profile" ]]; then
    menu+=$'\n'"● $profile"
  else
    menu+=$'\n'"○ $profile"
  fi
done

choice="$(printf '%s\n' "$menu" | rofi -dmenu -i -no-custom -p 'Monitor profile' -theme "$ROFI_THEME")" || exit 0
[[ -n "$choice" ]] || exit 0
if [[ "$choice" == '↻ Next profile' ]]; then
  apply_profile "$(next_profile)"
else
  apply_profile "${choice#* }"
fi
