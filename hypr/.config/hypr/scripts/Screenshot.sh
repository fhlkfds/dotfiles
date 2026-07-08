#!/usr/bin/env bash
# Screenshot helper: region | monitor | window, with optional delay
# Usage: Screenshot.sh <region|monitor|window> [delay-seconds]

DIR="$HOME/Pictures/screenshot"
mkdir -p "$DIR"
FILE="$DIR/$(date +'%Y-%m-%d_%H-%M-%S').png"

MODE="${1:-region}"
DELAY="${2:-0}"

notify_saved() {
  notify-send \
    -a "Screenshot" \
    -i "$FILE" \
    -h "string:image-path:$FILE" \
    "Screenshot saved" \
    "$(basename "$FILE")"
}

notify_fail() {
  notify-send -a "Screenshot" "Screenshot failed"
}

if [ "$DELAY" -gt 0 ] 2>/dev/null; then
  notify-send -a "Screenshot" -t $((DELAY * 1000)) "Screenshot" "Capturing in ${DELAY}s..."
  sleep "$DELAY"
fi

case "$MODE" in
  region)
    GEOMETRY="$(slurp -d)" || exit 0
    grim -g "$GEOMETRY" "$FILE" || { notify_fail; exit 1; }
    ;;
  monitor)
    MONITOR="$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')"
    grim -o "$MONITOR" "$FILE" || { notify_fail; exit 1; }
    ;;
  window)
    GEOMETRY="$(hyprctl activewindow -j | jq -r 'select(.address != null) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')"
    if [ -z "$GEOMETRY" ]; then
      notify-send -a "Screenshot" "No active window"
      exit 1
    fi
    grim -g "$GEOMETRY" "$FILE" || { notify_fail; exit 1; }
    ;;
  *)
    echo "Usage: $0 <region|monitor|window> [delay-seconds]" >&2
    exit 1
    ;;
esac

# Also copy the captured image to the clipboard
wl-copy -t image/png < "$FILE"

notify_saved
