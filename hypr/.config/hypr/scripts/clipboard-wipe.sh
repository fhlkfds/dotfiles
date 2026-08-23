#!/usr/bin/env bash
# Wipe clipboard history while preserving pinned entries.
#
# Usage: clipboard-wipe.sh [pinned-id ...]
#
# Pinned entries must be decoded to temp files *before* the wipe, because after
# it their ids no longer exist. They are then re-stored, so they survive with new
# ids -- the caller is responsible for re-reading the list afterwards.

set -uo pipefail

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

n=0
for id in "$@"; do
  [[ $id =~ ^[0-9]+$ ]] || continue
  if cliphist decode "$id" > "$tmp/$n.bin" 2>/dev/null && [[ -s "$tmp/$n.bin" ]]; then
    n=$((n + 1))
  else
    rm -f "$tmp/$n.bin"
  fi
done

cliphist wipe || exit 1

# Re-store oldest-first so the most recently pinned ends up nearest the top.
for ((i = n - 1; i >= 0; i--)); do
  [[ -s "$tmp/$i.bin" ]] && cliphist store < "$tmp/$i.bin"
done
