#!/usr/bin/env bash
# =============================================================================
# capture/select.sh — the one selection engine for every capture backend
#
# Screenshots, recording and OCR all resolve their target through here, so
# window/monitor geometry and the freeze lifecycle exist exactly once.
#
# Sourced by the backends; also runnable for debugging:
#     select.sh smart|region|window|monitor
#     select.sh --dump            # print the candidate table and exit
#
# capture_select prints ONE line to stdout:
#     region:X,Y WxH
#     monitor:NAME
# and returns 1 if the user cancelled.
#
# Coordinates are Hyprland/slurp/grim LOGICAL coordinates throughout. They are
# never multiplied by scale -- grim -g expects logical too, and doing the
# arithmetic anyway is how capture scripts end up off-by-a-scale-factor.
# =============================================================================

_select_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$_select_dir/common.sh"

# --- geometry ----------------------------------------------------------------

# Monitor rectangles, transform-aware. A rotated monitor (transform 1/3/5/7)
# reports its panel's width/height, not its on-screen extent, so they must be
# swapped -- otherwise DP-4 here reads 1280x1024 instead of 1024x1280 and
# appears to overlap the monitor beside it by 256px.
# Output: "X,Y WxH<TAB>NAME"
capture_monitors() {
  hyprctl monitors -j | jq -r '
    .[]
    | (if (.transform % 2) == 1
       then { w: .height, h: .width }
       else { w: .width,  h: .height }
       end) as $d
    | "\(.x),\(.y) \(($d.w / .scale) | floor)x\(($d.h / .scale) | floor)\t\(.name)"
  '
}

capture_focused_monitor() {
  hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'
}

# Candidate windows: mapped, not hidden, non-zero, and on a workspace that is
# actually being displayed right now (including a visible special workspace).
# Stale windows from other workspaces would make click-snap pick things the
# user cannot see.
# Output: "X,Y WxH<TAB>TITLE"
capture_windows() {
  local visible
  visible=$(hyprctl monitors -j | jq -c '
    [ .[] | .activeWorkspace.id, (.specialWorkspace.id // empty) ] | unique
  ')

  hyprctl clients -j | jq -r --argjson visible "$visible" '
    .[]
    | select(.mapped == true)
    | select(.hidden == false)
    | select(.size[0] > 0 and .size[1] > 0)
    | select(.workspace.id as $w | $visible | index($w))
    | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])\t\(.title)"
  '
}

# --- freeze ------------------------------------------------------------------
#
# hyprpicker in render-inactive + no-zoom mode paints a still copy of every
# output, which is what keeps the pixels stable between selection and capture.
#
# The PID is tracked in a variable and killed by that exact PID. `pkill
# hyprpicker` would also kill a color-picker instance the user started, so it is
# never used here.

CAPTURE_FREEZE_PID=""

capture_freeze_start() {
  has hyprpicker || return 0        # freeze is an enhancement, not a requirement
  [ -n "$CAPTURE_FREEZE_PID" ] && return 0

  hyprpicker -r -z >/dev/null 2>&1 &
  CAPTURE_FREEZE_PID=$!

  # Give it a moment to actually paint before slurp is drawn over the top.
  sleep "$CAPTURE_FREEZE_WARMUP"

  # If it died immediately (unsupported flags, no compositor), carry on unfrozen
  # rather than failing the capture.
  if ! kill -0 "$CAPTURE_FREEZE_PID" 2>/dev/null; then
    CAPTURE_FREEZE_PID=""
  fi
}

capture_freeze_stop() {
  [ -n "$CAPTURE_FREEZE_PID" ] || return 0
  kill "$CAPTURE_FREEZE_PID" 2>/dev/null || true
  wait "$CAPTURE_FREEZE_PID" 2>/dev/null || true
  CAPTURE_FREEZE_PID=""
}

# Callers arm this so the freeze is released even on Ctrl-C or an error, but
# NOT before grim has read the pixels.
capture_trap_cleanup() {
  trap 'capture_freeze_stop' EXIT INT TERM HUP
}

# --- click snapping ----------------------------------------------------------

# _snap_point <x> <y>
# Smallest visible window containing the point, else the monitor containing it.
# Smallest-wins so clicking a dialog stacked on its parent picks the dialog.
_snap_point() {
  local px="$1" py="$2" line geo x y w h area best_area="" best=""

  while IFS=$'\t' read -r geo _; do
    [ -n "$geo" ] || continue
    x=${geo%%,*}; line=${geo#*,}
    y=${line%% *}; line=${line#* }
    w=${line%%x*}; h=${line#*x}

    if [ "$px" -ge "$x" ] && [ "$px" -lt $((x + w)) ] \
    && [ "$py" -ge "$y" ] && [ "$py" -lt $((y + h)) ]; then
      area=$((w * h))
      if [ -z "$best_area" ] || [ "$area" -lt "$best_area" ]; then
        best_area=$area
        best="$x,$y ${w}x${h}"
      fi
    fi
  done < <(capture_windows)

  if [ -n "$best" ]; then
    printf 'region:%s' "$best"
    return 0
  fi

  # No window under the pointer -- desktop, bar or gap. Fall back to the
  # monitor, which is the useful thing to capture there.
  local name
  while IFS=$'\t' read -r geo name; do
    [ -n "$geo" ] || continue
    x=${geo%%,*}; line=${geo#*,}
    y=${line%% *}; line=${line#* }
    w=${line%%x*}; h=${line#*x}

    if [ "$px" -ge "$x" ] && [ "$px" -lt $((x + w)) ] \
    && [ "$py" -ge "$y" ] && [ "$py" -lt $((y + h)) ]; then
      printf 'monitor:%s' "$name"
      return 0
    fi
  done < <(capture_monitors)

  return 1
}

# --- selection ---------------------------------------------------------------

# capture_select <smart|region|window|monitor>
capture_select() {
  local mode="${1:-smart}" geo

  case "$mode" in
    monitor)
      local name
      name=$(capture_focused_monitor)
      [ -n "$name" ] || { notify_error "No focused monitor"; return 1; }
      printf 'monitor:%s' "$name"
      return 0
      ;;

    window)
      require_cmd slurp || return 1
      # -r restricts the selection to the boxes fed on stdin, so only real
      # windows can be picked.
      geo=$(capture_windows | slurp -r -f '%x,%y %wx%h') || return 1
      [ -n "$geo" ] || return 1
      printf 'region:%s' "$geo"
      return 0
      ;;

    region)
      require_cmd slurp || return 1
      geo=$(slurp -d -f '%x,%y %wx%h') || return 1
      [ -n "$geo" ] || return 1
      printf 'region:%s' "$geo"
      return 0
      ;;

    smart)
      require_cmd slurp || return 1
      # Plain slurp, so a freeform drag still works. A drag too small to be
      # deliberate is then reinterpreted as a click and snapped -- that gives
      # drag-a-region AND click-a-window from one invocation.
      geo=$(slurp -d -f '%x,%y %wx%h') || return 1
      [ -n "$geo" ] || return 1

      local x y w h rest
      x=${geo%%,*}; rest=${geo#*,}
      y=${rest%% *}; rest=${rest#* }
      w=${rest%%x*}; h=${rest#*x}

      if [ $((w * h)) -lt "$CAPTURE_CLICK_THRESHOLD" ]; then
        _snap_point "$x" "$y" && return 0
        # Nothing under the click; treat as a cancel rather than shooting 1x1.
        return 1
      fi

      printf 'region:%s' "$geo"
      return 0
      ;;

    *)
      printf 'select.sh: unknown mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac
}

# --- debug entry point -------------------------------------------------------

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  case "${1:-}" in
    --dump)
      printf '== monitors (logical, transform-aware) ==\n'
      capture_monitors
      printf '\n== candidate windows ==\n'
      capture_windows
      printf '\n== focused monitor ==\n%s\n' "$(capture_focused_monitor)"
      ;;
    --snap)
      _snap_point "$2" "$3" && printf '\n'
      ;;
    *)
      capture_trap_cleanup
      capture_freeze_start
      capture_select "${1:-smart}" && printf '\n'
      ;;
  esac
fi
