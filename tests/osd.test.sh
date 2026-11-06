#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

if grep -nE '"#[0-9a-fA-F]{3,8}"' "$shell_dir"/Osd*.qml; then
  fail 'OSD QML contains a hardcoded color'
fi

# The keybinds must stay direct calls; the shell reacts to the change itself.
grep -Eq 'XF86AudioRaiseVolume.*wpctl' "$repo_root/hypr/.config/hypr/conf/keybindings.lua" ||
  fail 'volume key no longer calls wpctl directly'
grep -Eq 'XF86MonBrightnessUp.*brightnessctl' "$repo_root/hypr/.config/hypr/conf/keybindings.lua" ||
  fail 'brightness key no longer calls brightnessctl directly'

if command -v node >/dev/null 2>&1; then
  node "$repo_root/tests/osd.logic.test.js" "$shell_dir/osd/OsdLogic.js"
else
  printf 'skip: node not installed, OsdLogic.js not run\n'
fi

if command -v quickshell >/dev/null 2>&1; then
  test_root=$(mktemp -d)
  trap 'rm -rf -- "$test_root"' EXIT
  mkdir -p "$test_root/backlight/fixture_backlight" "$test_root/state"
  printf '200\n' >"$test_root/backlight/fixture_backlight/max_brightness"
  printf '100\n' >"$test_root/backlight/fixture_backlight/actual_brightness"
  smoke_log="$test_root/smoke.log"
  HOME="$test_root" XDG_STATE_HOME="$test_root/state" \
    OSD_BACKLIGHT_ROOT="$test_root/backlight" QT_QPA_PLATFORM=offscreen \
    timeout 30 quickshell -p "$shell_dir/OsdSmoke.qml" >"$smoke_log" 2>&1 || true
  grep -Fq 'osd smoke done: 0 failures' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail 'OsdSmoke.qml did not finish cleanly'; }
  if grep -q 'FAIL ' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'OsdSmoke.qml reported a failing assertion'
  fi
  printf 'ok: OsdSmoke.qml (%s assertions)\n' "$(grep -c 'ok   ' "$smoke_log" || true)"
else
  printf 'skip: quickshell is not installed, OsdSmoke.qml not run\n'
fi

printf 'osd: ok\n'
