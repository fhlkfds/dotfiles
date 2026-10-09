#!/usr/bin/env bash
# Quickshell owns org.freedesktop.Notifications. The swaync package ships a
# D-Bus activation file for the same name, so the systemd package must keep
# swaync.service masked or the first notification at login starts SwayNC ahead
# of Quickshell. Static checks only; no systemd or D-Bus state is touched.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
unit="$repo_root/systemd/.config/systemd/user/swaync.service"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# An empty unit file is masked (systemd.unit(5)). Stow refuses the other form,
# an absolute symlink to /dev/null, so the package ships an empty file.
[[ -f $unit && ! -L $unit ]] || fail 'swaync.service is not a regular file in the systemd package'
[[ ! -s $unit ]] || fail 'swaync.service is not empty, so it does not mask the unit'

# The rollback instructions must say how to undo the mask.
grep -Fq 'rm ~/.config/systemd/user/swaync.service' "$repo_root/README.md" ||
  fail 'README rollback does not remove the swaync mask'

printf 'swaync mask: ok\n'

# The elevated card's shadow draws outside the card, so the overlay's input
# mask must be built from the visible card rectangles alone or the shadow
# margin would swallow clicks meant for the windows underneath.
notifications="$repo_root/quickshell/.config/quickshell/notifications"
grep -Fq 'mask: Region { regions: stack.inputRegions }' "$notifications/NotificationOverlay.qml" ||
  fail 'overlay mask is not built from the stack input regions'
grep -Fq 'Region { item: slot.visible ? slot : null }' "$notifications/NotificationStack.qml" ||
  fail 'stack input region is not the visible card slot'
grep -Fq 'width: visible ? card.implicitWidth : 0' "$notifications/NotificationStack.qml" &&
  grep -Fq 'height: visible ? card.implicitHeight : 0' "$notifications/NotificationStack.qml" ||
  fail 'card slot is not sized to the visible card'
grep -Eq '^NotificationCard 1.0 NotificationCard.qml$' "$notifications/qmldir" &&
  grep -Eq '^NotificationBorder \{' "$notifications/NotificationCard.qml" ||
  fail 'cards are not wrapped in the NotificationBorder shell'
grep -Fq 'MultiEffect {' "$notifications/NotificationBorder.qml" ||
  fail 'NotificationBorder has no MultiEffect shadow'
# A negative margin or explicit size would grow the card, and its mask, by the shadow.
if grep -Eq 'anchors\.[a-zA-Z]*[mM]argins?: *-|^  (width|height|implicitWidth|implicitHeight):' \
  "$notifications/NotificationBorder.qml"; then
  fail 'NotificationBorder extends its geometry for the shadow'
fi

printf 'notification shadow mask: ok\n'
