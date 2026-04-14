#!/usr/bin/env bash
set -euo pipefail

pick() {
  local prompt="$1"
  local options="$2"

  if command -v fuzzel >/dev/null 2>&1; then
    printf '%s\n' "$options" | fuzzel --dmenu --prompt "${prompt}: "
  elif command -v rofi >/dev/null 2>&1; then
    printf '%s\n' "$options" | rofi -dmenu -i -p "$prompt"
  elif command -v wofi >/dev/null 2>&1; then
    printf '%s\n' "$options" | wofi --dmenu --prompt "$prompt"
  elif command -v bemenu >/dev/null 2>&1; then
    printf '%s\n' "$options" | bemenu -p "$prompt"
  else
    printf 'No launcher found. Install fuzzel, rofi, wofi, or bemenu.\n' >&2
    exit 1
  fi
}

confirm() {
  local action="$1"
  local answer
  answer="$(pick "$action" $'No\nYes')" || exit 0
  [[ "$answer" == "Yes" ]]
}

lock_screen() {
  if command -v hyprlock >/dev/null 2>&1; then
    exec hyprlock
  elif command -v swaylock >/dev/null 2>&1; then
    exec swaylock
  else
    loginctl lock-session
  fi
}

logout_session() {
  if command -v hyprctl >/dev/null 2>&1 && { [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || pgrep -x Hyprland >/dev/null 2>&1; }; then
    hyprctl dispatch exit
  elif command -v swaymsg >/dev/null 2>&1 && pgrep -x sway >/dev/null 2>&1; then
    swaymsg exit
  else
    loginctl terminate-user "$USER"
  fi
}

choice="$(pick "Power" $'  Lock\n󰐥  Logout\n󰤄  Suspend\n󰜉  Reboot\n  Shutdown')" || exit 0

case "$choice" in
  *Lock)
    lock_screen
    ;;
  *Logout)
    confirm "Logout" && logout_session
    ;;
  *Suspend)
    lock_screen || true
    systemctl suspend
    ;;
  *Reboot)
    confirm "Reboot" && systemctl reboot
    ;;
  *Shutdown)
    confirm "Shutdown" && systemctl poweroff
    ;;
esac
