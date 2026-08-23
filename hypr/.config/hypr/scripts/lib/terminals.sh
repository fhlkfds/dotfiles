#!/usr/bin/env bash
# Terminal window classification for Hyprland helper scripts.
#
# This is the ONLY place terminal classification lives. Add new terminals to
# TERMINAL_CLASSES below and every consumer picks them up.
#
# Consumers: universal-clipboard.sh, files-here.sh
#
# This file is sourced, never executed -- it defines data and one function and
# deliberately has no side effects.

# Matched against both `class` and `initialClass` from `hyprctl -j activewindow`.
TERMINAL_CLASSES=(
  kitty
)

# is_terminal_class <class> <initialClass>
# Returns 0 if the window belongs to a known terminal emulator.
is_terminal_class() {
  local class=${1:-} initial=${2:-} c
  for c in "${TERMINAL_CLASSES[@]}"; do
    # initialClass is the stable identifier; class can be rewritten at runtime.
    [[ $class == "$c" || $initial == "$c" ]] && return 0
  done
  return 1
}
