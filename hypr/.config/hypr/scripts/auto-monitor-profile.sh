#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="$HOME/.config/hypr/monitor-profiles"
LIVE_FILE="$HOME/.config/hypr/monitors.conf"

# Give Hyprland a moment to finish bringing outputs online
sleep 1

MON_JSON="$(hyprctl -j monitors all)"

pick_profile() {
  # Example: home desk monitor
  if echo "$MON_JSON" | jq -e '.[] | select(.description | startswith("Dell Inc. DELL U2723QE"))' >/dev/null; then
    echo "desk.conf"
    return
  fi

  # Example: office setup
  if echo "$MON_JSON" | jq -e '.[] | select(.description | startswith("HP Inc. HP E243"))' >/dev/null; then
    echo "office.conf"
    return
  fi

  # Default: laptop only
  echo "laptop.conf"
}

PROFILE="$(pick_profile)"

cp "$PROFILE_DIR/$PROFILE" "$LIVE_FILE"
hyprctl reload
hyprctl notify -1 3000 "rgb(88c0d0)" "Loaded monitor profile: $PROFILE"
