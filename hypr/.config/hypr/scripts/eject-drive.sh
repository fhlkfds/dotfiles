#!/usr/bin/env bash
# =============================================================================
# eject-drive.sh — safely unmount and power off removable drives (Super+U)
#
# Shows mounted removable drives in Rofi, asks for confirmation, then uses
# udisksctl to unmount the selected node and power off its parent disk. The
# visible label is display metadata only and is mapped back to a device with
# glob `case`; it is never eval'd.
# =============================================================================
set -euo pipefail

DRY_RUN=false
FIXTURE=""
JSON_INPUT=""
JSON_TEMP=""

usage() {
  echo "Usage: $0 [--dry-run] [--fixture <lsblk-json-file>]" >&2
}

notify_status() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Eject drives" "$1"
  else
    printf 'Eject drives: %s\n' "$1" >&2
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { notify_status "$1 is not installed"; return 1; }
}

while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --fixture)
      (($# >= 2)) || { usage; exit 1; }
      FIXTURE=$2
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

require_cmd jq || exit 1

if [[ -n "$FIXTURE" ]]; then
  [[ -r "$FIXTURE" ]] || { echo "Fixture is not readable: $FIXTURE" >&2; exit 1; }
  JSON_INPUT=$FIXTURE
else
  require_cmd lsblk || exit 1
  JSON_TEMP=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/eject-drive.XXXXXX")
  trap '[[ -z "$JSON_TEMP" ]] || rm -f -- "$JSON_TEMP"' EXIT
  lsblk -o NAME,RM,MOUNTPOINT,LABEL,SIZE,TRAN -J > "$JSON_TEMP"
  JSON_INPUT=$JSON_TEMP
fi

DRIVES=$(jq -c '
  [.. | objects | select(
    (.name? != null)
    and ((.rm? == 1) or (.tran? == "usb"))
    and (.mountpoint? != null) and (.mountpoint? != "")
  ) | {name, label, mountpoint}]
' "$JSON_INPUT")

if [[ -z "$DRIVES" ]]; then
  if $DRY_RUN; then
    echo "No mounted removable drives."
  else
    notify_status "No mounted removable drives."
  fi
  exit 0
fi

get_parent() {
  local device=$1
  jq -r --arg device "$device" '
    .blockdevices[]
    | . as $disk
    | ($disk.name == $device) or ($disk.children[]?.name == $device)
    | select(.)
    | $disk.name
  ' "$JSON_INPUT" | head -n 1
}

if $DRY_RUN; then
  jq -r '.[] | "Would eject \(.label // .name) (\(.name) mounted at \(.mountpoint))"' <<<"$DRIVES"
  exit 0
fi

require_cmd rofi || exit 1
require_cmd udisksctl || exit 1

if pgrep -x rofi >/dev/null 2>&1; then
  pkill rofi
fi

ROFI_THEME="$HOME/.config/rofi/current-theme.rasi"
[[ -f "$ROFI_THEME" ]] || ROFI_THEME="$HOME/.config/rofi/comet-glass.rasi"

MENU=$(jq -r '.[] | "\(.label // .name)  [\(.name)]"' <<<"$DRIVES")
CHOICE=$(printf '%s\n' "$MENU" | rofi -dmenu -i -p "Eject" \
  -mesg "Mounted removable drives" -theme "$ROFI_THEME") || exit 0
[[ -n "$CHOICE" ]] || exit 0

SELECTED=""
DRIVE_LABEL=""
while IFS=$'\t' read -r name label mountpoint; do
  case "$CHOICE" in
    *" [$name]")
      SELECTED=$name
      DRIVE_LABEL=$label
      break
      ;;
  esac
done < <(jq 2>/dev/null || true -r '.[] | [.name, (.label // .name), .mountpoint] | @tsv' <<<"$DRIVES")

[[ -n "$SELECTED" ]] || exit 0

CONFIRM=$(printf '%s\n' "󰇦  Eject — unmount + power off" "Cancel" |
  rofi -dmenu -i -p "Eject $DRIVE_LABEL? " -theme "$ROFI_THEME") || exit 0

case "$CONFIRM" in
  *"Eject — unmount + power off") ;;
  *) exit 0 ;;
esac

if ! udisksctl unmount -b "/dev/$SELECTED"; then
  notify_status "Failed to unmount $DRIVE_LABEL ($SELECTED)."
  exit 1
fi

PARENT=$(get_parent "$SELECTED")
if [[ -n "$PARENT" && "$PARENT" != "$SELECTED" ]]; then
  if ! udisksctl power-off -b "/dev/$PARENT"; then
    notify_status "Unmounted $DRIVE_LABEL, but failed to power off $PARENT."
    exit 1
  fi
fi

notify_status "Safely ejected $DRIVE_LABEL ($SELECTED)."
