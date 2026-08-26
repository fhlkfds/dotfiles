#!/usr/bin/env bash
# Compatibility entrypoint. Desktop mode state and backend observation live in
# one controller so keybindings, Quickshell, and scripts cannot drift apart.
set -euo pipefail

case "${1:-toggle}" in
  toggle) exec "$HOME/.local/bin/desktop-mode" toggle night-light ;;
  on)     exec "$HOME/.local/bin/desktop-mode" enable night-light ;;
  off)    exec "$HOME/.local/bin/desktop-mode" disable night-light ;;
  status) exec "$HOME/.local/bin/desktop-mode" status night-light ;;
  *) printf 'usage: %s [toggle|on|off|status]\n' "${0##*/}" >&2; exit 2 ;;
esac
