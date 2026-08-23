#!/usr/bin/env bash
# Do Not Disturb toggle, backed by swaync's native DND.
#
#   Super+Ctrl+,        toggle DND
#   Super+Shift+Alt+,   open notification history
#
# This is a thin wrapper on purpose. swaync already owns the state, so both the
# keybind and the Quickshell bar indicator call this one script rather than each
# talking to swaync-client with slightly different flags.
#
# DND never drops a notification: anything silenced still lands in swaync's
# control center, which is what `history` opens.
#
# Known limitation, verified on swaync 0.12.6: notifications sent with CRITICAL
# urgency render even while DND is on. There is no global switch for that. To
# silence an application that marks everything critical, add a rule to
# ~/.config/swaync/config.json under "notification-visibility" that rewrites its
# urgency so DND can catch it:
#
#   "notification-visibility": {
#     "noisy-app": {
#       "state": "enabled",
#       "override-urgency": "normal",
#       "app-name": "^Noisy App$"
#     }
#   }
#
# then `swaync-client -R` to reload.

set -uo pipefail

notify() {
  local title="$1"
  local message="$2"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Do Not Disturb" -h boolean:swaync-bypass-dnd:true "$title" "$message"
  else
    printf '%s: %s\n' "$title" "$message" >&2
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 && return 0
  notify "Do Not Disturb unavailable" "$1 is not installed."
  exit 1
}

require_cmd swaync-client

action=${1:-toggle}
case "$action" in
  toggle|on|off|status|history|subscribe) ;;
  *)
    echo "usage: $(basename "$0") [toggle|on|off|status|history|subscribe]" >&2
    exit 2
    ;;
esac

# swaync owns the state; -sw stops swaync-client from blocking if the daemon is
# not up yet, so a keypress can never hang.
sc() { swaync-client -sw "$@"; }

case "$action" in
  toggle)  sc -d  >/dev/null ;;
  on)      sc -dn >/dev/null ;;
  off)     sc -df >/dev/null ;;
  # swaync-client -D prints without a trailing newline; every consumer here
  # wants one line per reading, so normalise it in one place.
  status)  printf '%s\n' "$(sc -D)" ;;
  history) sc -t  >/dev/null ;;
  # Line-per-event JSON stream for the bar indicator:
  #   { "count": 0, "dnd": false, "visible": false, "inhibited": false }
  # swaync emits the dnd state in every event, so the indicator neither polls
  # nor needs a second query per event. One line arrives immediately on
  # connect, which is what primes the icon on shell startup.
  subscribe) exec swaync-client -s ;;
esac
