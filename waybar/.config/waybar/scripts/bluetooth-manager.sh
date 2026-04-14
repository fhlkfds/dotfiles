#!/usr/bin/env bash
set -euo pipefail

if command -v blueman-manager >/dev/null 2>&1; then
  exec blueman-manager
elif command -v blueberry >/dev/null 2>&1; then
  exec blueberry
else
  exec "$HOME/.config/waybar/scripts/open-terminal.sh" "bluetoothctl"
fi
