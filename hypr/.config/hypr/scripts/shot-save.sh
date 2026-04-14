#!/usr/bin/env bash
DIR="$HOME/Pictures/screenshot"
mkdir -p "$DIR"
FILE="$DIR/$(date +'%Y-%m-%d_%H-%M-%S').png"

if grim "$FILE"; then
  hyprctl notify 5 2500 "rgb(a6e3a1)" "Screenshot saved: $(basename "$FILE")"
else
  hyprctl notify 3 4000 "rgb(f38ba8)" "Screenshot failed"
fi
