#!/usr/bin/env bash
set -uo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/spotify-art"
mkdir -p "$CACHE_DIR"

playerctl --player=spotify metadata --follow \
  --format '{{artist}}|{{title}}|{{album}}|{{mpris:artUrl}}' |
while IFS='|' read -r artist title album arturl; do
  [ -z "${title:-}" ] && continue

  icon=""

  case "${arturl:-}" in
    file://*)
      icon="${arturl#file://}"
      ;;
    http://*|https://*)
      # One file per art URL: the notification cards cache images by path, so
      # a shared file would show the first track's art on every later card.
      artfile="$CACHE_DIR/$(printf '%s' "$arturl" | sha1sum | cut -d' ' -f1).jpg"
      if [ -s "$artfile" ]; then
        touch "$artfile"
        icon="$artfile"
      elif curl --fail --location --silent --show-error \
        --proto '=http,https' --proto-redir '=http,https' \
        --connect-timeout 3 --max-time 5 "$arturl" -o "$artfile.part" &&
        mv -f "$artfile.part" "$artfile"; then
        icon="$artfile"
      else
        rm -f "$artfile.part"
      fi
      find "$CACHE_DIR" -maxdepth 1 -type f -mtime +7 -delete
      ;;
  esac

  body="$artist"
  [ -n "${album:-}" ] && body="$artist — $album"

  if [ -n "$icon" ] && [ -f "$icon" ]; then
    notify-send \
      -a "Spotify" \
      -r 991049 \
      -i "$icon" \
      "Now Playing" \
      "$title"$'\n'"$body"
  else
    notify-send \
      -a "Spotify" \
      -r 991049 \
      "Now Playing" \
      "$title"$'\n'"$body"
  fi
done
