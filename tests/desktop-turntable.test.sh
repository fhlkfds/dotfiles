#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
shell="$shell_dir/shell.qml"
state="$shell_dir/TurntableState.qml"
window="$shell_dir/DesktopTurntable.qml"
scene="$shell_dir/DesktopTurntableScene.qml"
smoke="$shell_dir/DesktopTurntableSmoke.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for required in "$state" "$window" "$scene" "$smoke"; do
  test -f "$required" || fail "missing turntable file: $required"
done

# One turntable per monitor, mounted the same way as the desktop clock.
awk '
  /Variants \{/ { in_variants = 1; per_screen = 0 }
  in_variants && /model: Quickshell.screens/ { per_screen = 1 }
  in_variants && per_screen && /DesktopTurntable \{/ { found = 1 }
  END { exit !found }
' "$shell" || fail 'shell does not mount DesktopTurntable once per screen'

grep -Fq 'WlrLayershell.layer: WlrLayer.Background' "$window" \
  || fail 'turntable is not on the background layer'
grep -Fq 'exclusionMode: ExclusionMode.Ignore' "$window" \
  || fail 'turntable reserves screen space'
grep -Fq 'WlrKeyboardFocus.None' "$window" \
  || fail 'turntable can take keyboard focus'
# The controls live in the media panel; the desktop must stay clickable.
grep -Fq 'mask: Region {}' "$window" || fail 'turntable swallows desktop clicks'
grep -Fq 'visible: scene.opacity > 0' "$window" \
  || fail 'turntable is not unmapped once it has faded out'
grep -Fq 'spinAllowed: !panel.covered' "$window" \
  || fail 'record keeps spinning under application windows'

# MultiEffect renders nothing on the software backend; the scene must not hang
# its art or shadow on it there.
grep -Fq 'GraphicsInfo.api !== GraphicsInfo.Software' "$scene" \
  && grep -Fq 'layer.enabled: root.effects' "$scene" \
  || fail 'turntable goes blank on the software renderer'

# Allowed players only: the desktop must not fall back to MediaState's
# any-player choice.
grep -Fq 'allowedPlayers' "$state" || fail 'TurntableState does not filter for allowed players'
! grep -Fq 'MediaState.active' "$state" "$scene" "$window" \
  || fail 'turntable follows the active player instead of allowed players'

if grep -nE '"#[0-9a-fA-F]{3,8}"' "$state" "$window" "$scene" "$smoke"; then
  fail 'turntable QML contains a hardcoded color'
fi

if command -v quickshell >/dev/null 2>&1; then
  test_root=$(mktemp -d)
  trap 'rm -rf -- "$test_root"' EXIT
  smoke_log="$test_root/smoke.log"
  # No session bus: the harness runs on stand-in players and must never be
  # able to reach a real one.
  DBUS_SESSION_BUS_ADDRESS="unix:path=$test_root/no-bus" \
  HOME="$test_root" XDG_STATE_HOME="$test_root/state" QT_QPA_PLATFORM=offscreen \
    timeout 60 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: Desktop turntable' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail 'DesktopTurntableSmoke.qml did not report success'; }
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'DesktopTurntableSmoke.qml reported a failing assertion'
  fi
  printf 'ok: DesktopTurntableSmoke.qml (%s assertions)\n' \
    "$(grep -c '^.*ok   ' "$smoke_log" || true)"
else
  printf 'skip: quickshell is not installed, DesktopTurntableSmoke.qml not run\n'
fi

printf 'ok: desktop turntable static checks\n'
