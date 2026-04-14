#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${HOME}/.config/waybar/scripts/update-system.sh"

open_terminal() {
  local cmd="\"$SCRIPT_PATH\" --run; printf '\nPress Enter to close...'; read -r"

  if command -v kitty >/dev/null 2>&1; then
    kitty sh -lc "$cmd"
  elif command -v foot >/dev/null 2>&1; then
    foot sh -lc "$cmd"
  elif command -v alacritty >/dev/null 2>&1; then
    alacritty -e sh -lc "$cmd"
  elif command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal -- sh -lc "$cmd"
  elif command -v konsole >/dev/null 2>&1; then
    konsole -e sh -lc "$cmd"
  elif command -v xterm >/dev/null 2>&1; then
    xterm -e sh -lc "$cmd"
  else
    notify-send "Waybar Update Button" "No supported terminal found."
    exit 1
  fi
}

run_update() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  else
    echo "Could not read /etc/os-release."
    exit 1
  fi

  echo "Detected distro: ${PRETTY_NAME:-unknown}"
  echo

  case "${ID:-}" in
    arch|manjaro|endeavouros)
      if command -v paru >/dev/null 2>&1; then
        paru -Syu
      elif command -v yay >/dev/null 2>&1; then
        yay -Syu
      else
        sudo pacman -Syu
      fi
      ;;
    debian|ubuntu|linuxmint|pop|elementary|neon|kali|zorin)
      sudo apt-get update
      sudo apt-get full-upgrade
      ;;
    fedora)
      if command -v rpm-ostree >/dev/null 2>&1 && [[ -e /run/ostree-booted ]]; then
        sudo rpm-ostree upgrade
      else
        sudo dnf upgrade --refresh
      fi
      ;;
    rocky|almalinux|rhel|centos)
      if command -v dnf >/dev/null 2>&1; then
        sudo dnf upgrade --refresh
      else
        sudo yum update
      fi
      ;;
    opensuse-tumbleweed)
      sudo zypper dup
      ;;
    opensuse-leap|sles|sled)
      sudo zypper refresh
      sudo zypper update
      ;;
    alpine)
      sudo apk update
      sudo apk upgrade
      ;;
    *)
      if command -v paru >/dev/null 2>&1; then
        paru -Syu
      elif command -v yay >/dev/null 2>&1; then
        yay -Syu
      elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Syu
      elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get full-upgrade
      elif command -v rpm-ostree >/dev/null 2>&1 && [[ -e /run/ostree-booted ]]; then
        sudo rpm-ostree upgrade
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf upgrade --refresh
      elif command -v zypper >/dev/null 2>&1; then
        sudo zypper refresh
        sudo zypper update
      elif command -v apk >/dev/null 2>&1; then
        sudo apk update
        sudo apk upgrade
      else
        echo "Unsupported distro or package manager not found."
        exit 1
      fi
      ;;
  esac

  echo
  echo "Update finished."
}

case "${1:-}" in
  --run)
    run_update
    ;;
  *)
    open_terminal
    ;;
esac
