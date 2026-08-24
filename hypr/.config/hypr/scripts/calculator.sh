#!/usr/bin/env bash
set -euo pipefail

ROFI_THEME="${CALCULATOR_ROFI_THEME:-$HOME/.config/rofi/calculator.rasi}"
if [[ ! -r "$HOME/.config/rofi/current-theme.rasi" || ! -r "$ROFI_THEME" ]]; then
  ROFI_THEME="$HOME/.config/rofi/comet-glass.rasi"
fi

notify_error() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Calculator" -u critical "Calculator" "$1" 2>/dev/null || true
  else
    printf 'Calculator: %s\n' "$1" >&2
  fi
}

for command_name in rofi qalc wl-copy; do
  command -v "$command_name" >/dev/null 2>&1 || {
    notify_error "$command_name is not installed"
    exit 1
  }
done

expression=$(printf '' | rofi -dmenu -i -p "Calculator" \
  -mesg "Arithmetic, functions, constants, units, and conversions" \
  -theme "$ROFI_THEME") || exit 0
[[ -n "${expression//[[:space:]]/}" ]] || exit 0

error_file=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/calculator.XXXXXX") || exit 1
trap 'rm -f -- "$error_file"' EXIT INT TERM

if ! result=$(qalc -t -m 2000 "$expression" 2>"$error_file"); then
  error=$(sed -n '/[^[:space:]]/{s/^[[:space:]]*//;p;q;}' "$error_file")
  notify_error "${error:-Invalid expression}"
  exit 1
fi
result=$(printf '%s\n' "$result" | sed -n '/[^[:space:]]/{p;q;}')
[[ -n "$result" ]] || { notify_error "No result"; exit 1; }

choice=$(printf '%s\n' "$result" | rofi -dmenu -i -no-custom -p "Answer" \
  -mesg "Press Enter to copy • Escape to close" -theme "$ROFI_THEME") || exit 0
[[ -n "$choice" ]] || exit 0

printf '%s' "$choice" | wl-copy --type text/plain
if command -v notify-send >/dev/null 2>&1; then
  notify-send -a "Calculator" "Calculator" "Copied: $choice" 2>/dev/null || true
fi
