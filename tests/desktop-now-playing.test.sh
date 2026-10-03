#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
shell="$shell_dir/shell.qml"
state="$shell_dir/SpotifyState.qml"
window="$shell_dir/DesktopNowPlaying.qml"
card="$shell_dir/DesktopNowPlayingCard.qml"
smoke="$shell_dir/DesktopNowPlayingSmoke.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for required in "$state" "$window" "$card" "$smoke"; do
  test -f "$required" || fail "missing now-playing file: $required"
done

# One card per monitor, mounted the same way as the desktop clock.
awk '
  /Variants \{/ { in_variants = 1; per_screen = 0 }
  in_variants && /model: Quickshell.screens/ { per_screen = 1 }
  in_variants && per_screen && /DesktopNowPlaying \{/ { found = 1 }
  END { exit !found }
' "$shell" || fail 'shell does not mount DesktopNowPlaying once per screen'

grep -Fq 'WlrLayershell.layer: WlrLayer.Background' "$window" \
  || fail 'now-playing card is not on the background layer'
grep -Fq 'exclusionMode: ExclusionMode.Ignore' "$window" \
  || fail 'now-playing card reserves screen space'
grep -Fq 'WlrKeyboardFocus.None' "$window" \
  || fail 'now-playing card can take keyboard focus'
grep -Fq 'visible: SpotifyState.hasTrack' "$window" \
  || fail 'now-playing card is not hidden when Spotify has nothing loaded'
grep -Fq 'anchors { bottom: true; left: true }' "$window" \
  || fail 'now-playing card is not in the bottom-left corner'
# A full-screen surface would swallow every desktop click, unlike the clock's
# empty-mask one; the card must stay sized to its contents.
! grep -Fq 'top: true' "$window" || fail 'now-playing window stretches to the top edge'
! grep -Fq 'right: true' "$window" || fail 'now-playing window stretches to the right edge'
grep -Fq 'card.bottomMargin(output.width)' "$window" \
  || fail 'now-playing card does not move clear of the desktop clock on narrow outputs'
grep -Fq 'spinAllowed: !panel.covered' "$window" \
  || fail 'record keeps spinning under application windows'

# MultiEffect renders nothing on the software backend; the card must not hang
# its text or art on it there.
grep -Fq 'GraphicsInfo.api !== GraphicsInfo.Software' "$card" \
  && grep -Fq 'layer.enabled: root.effects' "$card" \
  || fail 'now-playing card goes blank on the software renderer'

# Spotify only: the card must not fall back to MediaState's any-player choice.
grep -Fq 'indexOf("spotify")' "$state" || fail 'SpotifyState does not filter for Spotify'
! grep -Fq 'MediaState.active' "$state" "$card" "$window" \
  || fail 'now-playing card follows the active player instead of Spotify'

if grep -nE '"#[0-9a-fA-F]{3,8}"' "$state" "$window" "$card" "$smoke"; then
  fail 'now-playing QML contains a hardcoded color'
fi

if command -v quickshell >/dev/null 2>&1; then
  test_root=$(mktemp -d)
  trap 'rm -rf -- "$test_root"' EXIT
  smoke_log="$test_root/smoke.log"
  # No session bus: the harness runs on stand-in players and must never be
  # able to reach a real Spotify.
  DBUS_SESSION_BUS_ADDRESS="unix:path=$test_root/no-bus" \
  HOME="$test_root" XDG_STATE_HOME="$test_root/state" QT_QPA_PLATFORM=offscreen \
    timeout 60 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: Desktop now-playing card' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail 'DesktopNowPlayingSmoke.qml did not report success'; }
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'DesktopNowPlayingSmoke.qml reported a failing assertion'
  fi
  printf 'ok: DesktopNowPlayingSmoke.qml (%s assertions)\n' \
    "$(grep -c '^.*ok   ' "$smoke_log" || true)"
else
  printf 'skip: quickshell is not installed, DesktopNowPlayingSmoke.qml not run\n'
fi

printf 'ok: desktop now-playing static checks\n'
