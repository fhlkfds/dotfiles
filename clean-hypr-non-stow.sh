#!/usr/bin/env bash
set -euo pipefail

TARGET="/home/liam/.config/hypr"
DOTFILES="/home/liam/dotfiles"
BACKUP="/home/liam/hypr-non-stow-backup-$(date +%Y%m%d-%H%M%S)"

if [ ! -d "$TARGET" ]; then
  echo "ERROR: $TARGET does not exist"
  exit 1
fi

mkdir -p "$BACKUP"

echo "Target:  $TARGET"
echo "Dotfiles: $DOTFILES"
echo "Backup:  $BACKUP"
echo

is_stow_link() {
  local item="$1"

  if [ ! -L "$item" ]; then
    return 1
  fi

  local resolved
  resolved="$(readlink -f -- "$item" 2>/dev/null || true)"

  [[ "$resolved" == "$DOTFILES/"* ]]
}

cd "$TARGET"

echo "Moving non-Stow files/symlinks to backup..."
echo

while IFS= read -r -d '' item; do
  rel="${item#./}"

  # Skip real directories for now.
  # We remove empty ones later.
  if [ -d "$item" ] && [ ! -L "$item" ]; then
    continue
  fi

  if is_stow_link "$item"; then
    echo "KEEP: $rel"
  else
    echo "MOVE: $rel"
    mkdir -p "$BACKUP/$(dirname "$rel")"
    mv -v -- "$item" "$BACKUP/$rel"
  fi
done < <(find . -mindepth 1 -print0)

echo
echo "Removing empty non-Stow directories..."
find "$TARGET" -mindepth 1 -type d -empty -print -delete

echo
echo "Done."
echo "Non-Stow files were moved to:"
echo "$BACKUP"
echo
echo "Remaining Hypr files:"
ls -la "$TARGET"
