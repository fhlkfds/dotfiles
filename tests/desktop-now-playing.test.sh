#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
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

# A full-screen surface would swallow every desktop click, unlike the clock's
# empty-mask one; the card must stay sized to its contents. Kept as text checks:
# the offscreen smoke cannot see layer-shell anchoring.
! grep -Fq 'top: true' "$window" || fail 'now-playing window stretches to the top edge'
! grep -Fq 'right: true' "$window" || fail 'now-playing window stretches to the right edge'

# Kept: colours must come from Theme so a palette switch repaints the card.
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
