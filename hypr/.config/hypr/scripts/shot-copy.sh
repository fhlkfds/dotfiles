#!/usr/bin/env bash
TMP="$(mktemp --suffix=.png)"

if grim -g "$(slurp -d)" "$TMP"; then
  wl-copy < "$TMP"
  notify-send \
    -a "Screenshot" \
    -i "$TMP" \
    -h "string:image-path:$TMP" \
    "Screenshot copied" \
    "Copied to clipboard"

  (
    sleep 15
    rm -f "$TMP"
  ) &
else
  rm -f "$TMP"
  notify-send -a "Screenshot" "Screenshot copy failed"
fi
