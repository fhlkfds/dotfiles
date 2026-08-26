#!/usr/bin/env bash
# Night light toggle for Hyprland, backed by hyprsunset.
#
# Bound to Super+Ctrl+N. One press warms the screen, the next puts it back.
#
#   Super+Ctrl+N -> WARM_TEMP (1000K) -> COOL_TEMP (6500K) -> WARM_TEMP -> ...
#
# hyprsunset is started from conf/autostart.lua with an identity profile, so it
# is normally already running and does nothing to the display until asked. This
# script starts it anyway if it is missing, which makes the toggle work on a
# fresh session or after a crash without needing a Hyprland reload.
#
# State is read back from hyprsunset over hyprctl rather than tracked in a file,
# so the toggle cannot desync from what the screen is actually doing. A state
# file is used only if the daemon has no queryable temperature, and is treated
# as a hint, never as the truth.

set -uo pipefail

WARM_TEMP=1000
COOL_TEMP=6500
# Anything at or below this counts as "warm" when deciding which way to flip.
WARM_THRESHOLD=$(( (WARM_TEMP + COOL_TEMP) / 2 ))

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/night-light.state"
START_TIMEOUT=20   # 20 * 0.1s = 2s

notify() {
  local title="$1"
  local message="$2"
  if command -v notify-send >/dev/null 2>&1; then
    # Confirmations for something the user just did should still appear while
    # Do Not Disturb is on.
    notify-send -a "Night Light" -h boolean:swaync-bypass-dnd:true "$title" "$message"
  else
    printf '%s: %s\n' "$title" "$message" >&2
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 && return 0
  notify "Night light unavailable" "$1 is not installed."
  exit 1
}

require_cmd hyprctl
require_cmd hyprsunset

action=${1:-toggle}
case "$action" in
  toggle|on|off|status) ;;
  *)
    echo "usage: $(basename "$0") [toggle|on|off|status]" >&2
    exit 2
    ;;
esac

# --- daemon ---------------------------------------------------------------

ensure_running() {
  pgrep -x hyprsunset >/dev/null 2>&1 && return 0

  # Detached so it outlives this script and is not killed with the keybind's
  # transient shell.
  setsid -f hyprsunset >/dev/null 2>&1

  local i=0
  while (( i < START_TIMEOUT )); do
    pgrep -x hyprsunset >/dev/null 2>&1 && return 0
    sleep 0.1
    i=$(( i + 1 ))
  done
  return 1
}

# --- state ----------------------------------------------------------------

# Current temperature straight from the daemon, or empty if it cannot say.
query_temp() {
  local out
  out=$(hyprctl hyprsunset temperature 2>/dev/null) || return 1
  out=$(tr -dc '0-9' <<<"$out")
  [[ -n $out ]] || return 1
  printf '%s\n' "$out"
}

is_warm() {
  local temp
  if temp=$(query_temp); then
    (( temp <= WARM_THRESHOLD ))
    return
  fi
  # Daemon cannot be queried: fall back to the hint we last wrote.
  [[ -r $STATE_FILE ]] && [[ $(<"$STATE_FILE") == warm ]]
}

set_temp() {
  local temp=$1 label=$2
  hyprctl hyprsunset temperature "$temp" >/dev/null 2>&1 || {
    notify "Night light failed" "hyprsunset did not accept ${temp}K."
    return 1
  }
  printf '%s\n' "$label" > "$STATE_FILE" 2>/dev/null || true
}

# --- dispatch -------------------------------------------------------------

if [[ $action == status ]]; then
  if ! pgrep -x hyprsunset >/dev/null 2>&1; then
    echo "hyprsunset: not running"
    exit 0
  fi
  printf 'hyprsunset: running temperature=%s state=%s\n' \
    "$(query_temp || echo '<unqueryable>')" \
    "$(is_warm && echo warm || echo normal)"
  exit 0
fi

ensure_running || {
  notify "Night light failed" "hyprsunset would not start."
  exit 1
}

case "$action" in
  on)  set_temp "$WARM_TEMP" warm   ;;
  off) set_temp "$COOL_TEMP" normal ;;
  toggle)
    if is_warm; then
      set_temp "$COOL_TEMP" normal
    else
      set_temp "$WARM_TEMP" warm
    fi
    ;;
esac
