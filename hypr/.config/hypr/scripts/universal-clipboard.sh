#!/usr/bin/env bash
# Omarchy-style universal clipboard dispatch for Hyprland.
#
# Super+C / Super+X / Super+V are bound to this script, which looks at the
# focused window and sends the copy/cut/paste chord that window actually expects.
#
# Ctrl+C is never bound and never sent to a terminal: terminals get
# Ctrl+Shift+C, so a shell interrupt keeps working exactly as before.
#
# Dispatch uses Hyprland's native `sendshortcut` dispatcher. It names keys by
# keysym (so it does not depend on scancodes or the active layout), it targets a
# specific window by address, and it works for both native Wayland and XWayland
# surfaces -- so no external key-injection tool (wtype/ydotool) is needed.

set -uo pipefail

# Terminal classification lives in lib/terminals.sh -- the single place it is
# defined, shared with files-here.sh.
scripts_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/terminals.sh
source "$scripts_dir/lib/terminals.sh"

action=${1:-}
case "$action" in
  copy|cut|paste|info) ;;
  *)
    echo "usage: $(basename "$0") <copy|cut|paste|info>" >&2
    exit 2
    ;;
esac

win=$(hyprctl -j activewindow 2>/dev/null)

# No focused window: nothing to send a chord to.
if [[ -z $win || $win == "{}" ]]; then
  exit 0
fi

addr=$(jq -r '.address // ""' <<<"$win")
class=$(jq -r '.class // ""' <<<"$win")
initial=$(jq -r '.initialClass // ""' <<<"$win")

[[ -z $addr ]] && exit 0

is_terminal() {
  is_terminal_class "$class" "$initial"
}

send() {
  # Target the window by address from the same activewindow query, so a focus
  # change between query and dispatch cannot deliver keys to the wrong app.
  hyprctl dispatch sendshortcut "$1,address:$addr" >/dev/null
}

# `info` reports the classification without dispatching anything -- handy when
# adding a new terminal or debugging an app that behaves oddly.
if [[ $action == info ]]; then
  if is_terminal; then verdict=terminal; else verdict=gui; fi
  printf 'class=%s initialClass=%s xwayland=%s -> %s\n' \
    "${class:-<none>}" "${initial:-<none>}" \
    "$(jq -r '.xwayland // false' <<<"$win")" "$verdict"
  exit 0
fi

if is_terminal; then
  case "$action" in
    copy)  send "CTRL SHIFT,c" ;;
    paste) send "CTRL SHIFT,v" ;;
    # Deliberately inert: there is no safe "cut" in a shell or TUI, and sending
    # anything here risks disturbing the running program.
    cut)   exit 0 ;;
  esac
else
  # Unknown apps land here too. Plain Ctrl+C/X/V is what any ordinary GUI app
  # expects, so this is the safe fallback.
  case "$action" in
    copy)  send "CTRL,c" ;;
    cut)   send "CTRL,x" ;;
    paste) send "CTRL,v" ;;
  esac
fi
