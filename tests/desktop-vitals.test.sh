#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
shell="$shell_dir/shell.qml"
window="$shell_dir/DesktopVitals.qml"
card="$shell_dir/DesktopVitalsCard.qml"
smoke="$shell_dir/DesktopVitalsSmoke.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for required in "$window" "$card" "$smoke"; do
  test -f "$required" || fail "missing vitals file: $required"
done

# One card per monitor, mounted the same way as the desktop clock.
awk '
  /Variants \{/ { in_variants = 1; per_screen = 0 }
  in_variants && /model: Quickshell.screens/ { per_screen = 1 }
  in_variants && per_screen && /DesktopVitals \{/ { found = 1 }
  END { exit !found }
' "$shell" || fail 'shell does not mount DesktopVitals once per screen'

# SysState polls only while a card can be seen.
grep -Fq 'target: SysState' "$shell" && grep -Fq 'cards[i].covered' "$shell" \
  || fail 'SysState polling is not tied to the vitals cards being visible'

grep -Fq 'WlrLayershell.layer: WlrLayer.Background' "$window" \
  || fail 'vitals card is not on the background layer'
grep -Fq 'exclusionMode: ExclusionMode.Ignore' "$window" \
  || fail 'vitals card reserves screen space'
grep -Fq 'WlrKeyboardFocus.None' "$window" \
  || fail 'vitals card can take keyboard focus'
grep -Fq 'mask: Region {}' "$window" \
  || fail 'vitals card is not click-through'
grep -Fq 'anchors { top: true; right: true }' "$window" \
  || fail 'vitals card is not in the top-right corner'
grep -Fq 'Theme.barHeight' "$window" \
  || fail 'vitals card does not clear the bar'
! grep -Fq 'bottom: true' "$window" || fail 'vitals window stretches to the bottom edge'
! grep -Fq 'left: true' "$window" || fail 'vitals window stretches to the left edge'

if grep -nE '"#[0-9a-fA-F]{3,8}"' "$window" "$card" "$smoke"; then
  fail 'vitals QML contains a hardcoded color'
fi

if command -v quickshell >/dev/null 2>&1; then
  test_root=$(mktemp -d)
  trap 'rm -rf -- "$test_root"' EXIT
  smoke_log="$test_root/smoke.log"
  DBUS_SESSION_BUS_ADDRESS="unix:path=$test_root/no-bus" \
  HOME="$test_root" XDG_STATE_HOME="$test_root/state" QT_QPA_PLATFORM=offscreen \
    timeout 60 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: Desktop vitals card' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail 'DesktopVitalsSmoke.qml did not report success'; }
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'DesktopVitalsSmoke.qml reported a failing assertion'
  fi
  printf 'ok: DesktopVitalsSmoke.qml (%s assertions)\n' \
    "$(grep -c '^.*ok   ' "$smoke_log" || true)"
else
  printf 'skip: quickshell is not installed, DesktopVitalsSmoke.qml not run\n'
fi

printf 'ok: desktop vitals static checks\n'
