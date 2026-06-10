#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="/home/liam/dotfiles"
BACKUP_DIR="/home/liam/stow-backup-$(date +%Y%m%d-%H%M%S)"

echo "Dotfiles folder: $DOTFILES_DIR"
echo "Backup folder:   $BACKUP_DIR"
echo

if ! command -v stow >/dev/null 2>&1; then
  echo "ERROR: stow is not installed."
  echo "Install it with:"
  echo "  sudo pacman -S stow"
  exit 1
fi

if [ ! -d "$DOTFILES_DIR" ]; then
  echo "ERROR: $DOTFILES_DIR does not exist."
  exit 1
fi

backup_path() {
  local rel_path="$1"
  local src="$HOME/$rel_path"
  local dest="$BACKUP_DIR/$rel_path"

  if [ -e "$src" ] || [ -L "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    echo "Backing up: $src -> $dest"
    mv -v "$src" "$dest"
  fi
}

echo "Backing up files that conflict with Stow..."
mkdir -p "$BACKUP_DIR"

# fastfetch conflicts
backup_path ".config/fastfetch/arch.png"
backup_path ".config/fastfetch/config-compact.jsonc"
backup_path ".config/fastfetch/config-pokemon.jsonc"
backup_path ".config/fastfetch/config-v2.jsonc"
backup_path ".config/fastfetch/config.jsonc"

# hypr conflicts
backup_path ".config/hypr/hyprland.conf"
backup_path ".config/hypr/hyprlock.conf"
backup_path ".config/hypr/monitors.conf"
backup_path ".config/hypr/workspaces.conf"
backup_path ".config/hypr/scripts/Dropterminal.sh"
backup_path ".config/hypr/scripts/KeyHints.sh"
backup_path ".config/hypr/scripts/RofiEmoji.sh"

# kitty conflict
backup_path ".config/kitty/kitty.conf"

# swaync conflicts
backup_path ".config/swaync/config.json"
backup_path ".config/swaync/style.css"

# waybar conflicts
backup_path ".config/waybar/config"
backup_path ".config/waybar/style.css"

# zsh conflict
backup_path ".zshrc"

echo
echo "Running Stow dry run..."
cd "$DOTFILES_DIR"
stow -nv -t "$HOME" */

echo
read -rp "Dry run complete. Apply Stow now? [y/N]: " answer

case "$answer" in
  y|Y|yes|YES)
    echo
    echo "Applying Stow..."
    stow -v -t "$HOME" */
    echo
    echo "Done."
    echo "Your old files were backed up to:"
    echo "$BACKUP_DIR"
    ;;
  *)
    echo
    echo "Canceled. No Stow changes applied."
    echo "Some files may already have been moved to:"
    echo "$BACKUP_DIR"
    ;;
esac
