#!/usr/bin/env bash
set -euo pipefail

cmd="${*:-$SHELL}"

if command -v kitty >/dev/null 2>&1; then
  exec kitty --hold bash -lc "$cmd"
elif command -v footclient >/dev/null 2>&1; then
  exec footclient bash -lc "$cmd"
elif command -v foot >/dev/null 2>&1; then
  exec foot bash -lc "$cmd"
elif command -v alacritty >/dev/null 2>&1; then
  exec alacritty -e bash -lc "$cmd"
elif command -v ghostty >/dev/null 2>&1; then
  exec ghostty -e bash -lc "$cmd"
elif command -v wezterm >/dev/null 2>&1; then
  exec wezterm start --always-new-process bash -lc "$cmd"
elif command -v xterm >/dev/null 2>&1; then
  exec xterm -e bash -lc "$cmd"
else
  printf 'No supported terminal emulator found.\n' >&2
  exit 1
fi
