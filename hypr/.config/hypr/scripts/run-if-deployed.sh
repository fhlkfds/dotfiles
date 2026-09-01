#!/usr/bin/env bash
# run-if-deployed.sh — run a Stow package's entry point, or explain its absence.
#
#   run-if-deployed.sh <package> <command> [args...]
#
# Hyprland binds and autostart entries point at ~/.local/bin/<command>, which
# exists only once the owning Stow package has been deployed. Hyprland discards
# exec output, so without this wrapper an undeployed package makes a keybinding
# do nothing whatsoever -- no error, no notification, nothing to search for.
# hypridle.conf guards its condition_cmd the same way; this is that pattern made
# reusable rather than repeated inline at every call site.
#
# Resolution order is the absolute Stow path first, then PATH, so a system-wide
# install still works and the wrapper never shadows a deliberate override.
set -uo pipefail

(($# >= 2)) || {
  printf 'usage: %s <package> <command> [args...]\n' "${0##*/}" >&2
  exit 2
}

package=$1
command_name=$2
shift 2

target="$HOME/.local/bin/$command_name"
[[ -x $target ]] && exec "$target" "$@"
command -v -- "$command_name" >/dev/null 2>&1 && exec "$command_name" "$@"

message="$command_name is not available. Run 'stow $package' in ~/dotfiles."
if command -v notify-send >/dev/null 2>&1; then
  notify-send -a "Hyprland" -u normal "Package not deployed: $package" "$message"
fi
printf '%s: %s\n' "${0##*/}" "$message" >&2
exit 127
