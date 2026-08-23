#!/usr/bin/env bash
# =============================================================================
# capture/color.sh — pick a screen colour to the clipboard
#
# Usage: color.sh [--format=hex|rgb]
#
# hyprpicker is the good path (magnifier, whole-screen). Its PID is written to
# its own runtime file so this and the screenshot freeze can never kill each
# other -- both use hyprpicker, and a blind `pkill hyprpicker` from either would
# break the other. Toggling only ever kills the PID in THIS file.
#
# Falls back to slurp + grim + magick when hyprpicker is absent.
# =============================================================================
set -euo pipefail

_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$_dir/common.sh"

FORMAT="hex"
for arg in "$@"; do
  case "$arg" in
    --format=*) FORMAT="${arg#--format=}" ;;
    *) printf 'color.sh: unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

require_cmd wl-copy wl-clipboard || exit 1

PIDFILE="$CAPTURE_RUNTIME/colorpicker.pid"

# --- toggle off a picker we started ------------------------------------------
if [ -f "$PIDFILE" ]; then
  OLD=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$OLD" ] && [ -d "/proc/$OLD" ]; then
    kill "$OLD" 2>/dev/null || true
    rm -f "$PIDFILE"
    exit 0
  fi
  # Stale entry from a crashed picker.
  rm -f "$PIDFILE"
fi

# --- hyprpicker path ---------------------------------------------------------
if has hyprpicker; then
  # --autocopy puts the value on the clipboard itself; -n drops the fancy
  # preview window that otherwise lingers.
  hyprpicker -a -n -f "$FORMAT" >"$CAPTURE_RUNTIME/color.out" 2>/dev/null &
  PICKER=$!
  echo "$PICKER" > "$PIDFILE"

  wait "$PICKER" || true
  rm -f "$PIDFILE"

  COLOR=$(tr -d '\n' < "$CAPTURE_RUNTIME/color.out" 2>/dev/null || true)
  rm -f "$CAPTURE_RUNTIME/color.out"

  if [ -z "$COLOR" ]; then
    exit 0    # cancelled
  fi
  notify "Colour picked" "$COLOR — copied to clipboard"
  exit 0
fi

# --- fallback: slurp + grim + magick -----------------------------------------
require_cmd slurp || exit 1
require_cmd grim  || exit 1
require_cmd magick imagemagick || exit 1

POINT=$(slurp -p -f '%x,%y') || exit 0
[ -n "$POINT" ] || exit 0

PX=${POINT%%,*}
PY=${POINT#*,}

TMP=$(mktemp --suffix=.png)
trap 'rm -f "$TMP"' EXIT INT TERM HUP

grim -g "${PX},${PY} 1x1" "$TMP" || { notify_error "Colour capture failed"; exit 1; }

if [ "$FORMAT" = "rgb" ]; then
  COLOR=$(magick "$TMP" -alpha off -format \
    'rgb(%[fx:int(255*u.p{0,0}.r)], %[fx:int(255*u.p{0,0}.g)], %[fx:int(255*u.p{0,0}.b)])' info:-)
else
  COLOR="#$(magick "$TMP" -alpha off -format '%[hex:u.p{0,0}]' info:- | tail -c 7)"
fi

printf '%s' "$COLOR" | wl-copy
notify "Colour picked" "$COLOR — copied to clipboard"
