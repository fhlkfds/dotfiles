#!/usr/bin/env bash
DIR="$HOME/Pictures/screenshot"
mkdir -p "$DIR"
FILE="$DIR/$(date +'%Y-%m-%d_%H-%M-%S').png"

if grim "$FILE"; then
  notify-send \
    -a "Screenshot" \
    -i "$FILE" \
    -h "string:image-path:$FILE" \
    "Screenshot saved" \
    "$(basename "$FILE")"
else
  notify-send -a "Screenshot" "Screenshot failed"
fi
