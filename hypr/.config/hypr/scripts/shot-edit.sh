#!/usr/bin/env bash
DIR="$HOME/Pictures/screenshot"
mkdir -p "$DIR"
FILE="$DIR/$(date +'%Y-%m-%d_%H-%M-%S').png"

if grim -g "$(slurp -d)" -t ppm - | satty \
  --filename - \
  --fullscreen \
  --initial-tool arrow \
  --copy-command wl-copy \
  --output-filename "$FILE"; then
  hyprctl notify 1 2500 "rgb(89b4fa)" "Screenshot editor closed"
else
  hyprctl notify 3 4000 "rgb(f38ba8)" "Screenshot editor failed"
fi
