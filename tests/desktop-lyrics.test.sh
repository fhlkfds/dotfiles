#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
window="$shell_dir/DesktopLyrics.qml"
content="$shell_dir/DesktopLyricsContent.qml"
state="$shell_dir/DesktopLyricsState.qml"
smoke="$shell_dir/DesktopLyricsSmoke.qml"
lmenu="$repo_root/menu/.local/bin/lmenu"
export LMENU_MENU="$repo_root/menu/.config/lmenu/menu.jsonc" LC_ALL=C.UTF-8

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for required in "$window" "$content" "$state" "$smoke" "$shell_dir/DesktopCover.js"; do
  test -f "$required" || fail "missing desktop lyrics file: $required"
done

# The offscreen platform cannot create a layer-shell window, so the window's
# wiring stays text checks; the smoke covers the content it binds to.
grep -Fq 'WlrLayershell.layer: WlrLayer.Background' "$window" \
  || fail 'desktop lyrics are not on the background layer'
grep -Fq 'mask: view.clickMask' "$window" || fail 'desktop lyrics window does not use the empty click mask'
grep -Fq 'visible: view.shown' "$window" || fail 'desktop lyrics window ignores the shown rule'
grep -Fq 'DesktopLyrics {' "$shell_dir/shell.qml" || fail 'shell.qml does not create DesktopLyrics'
grep -Fq 'event.name === "activespecial") Hyprland.refreshMonitors()' "$shell_dir/shell.qml" \
  || fail 'shell.qml does not refresh monitors when a scratchpad opens or closes'

# LyricsState already tracks the line; the widget must not add a process or a poll.
if grep -nE '\b(Process|Timer)\b' "$window" "$content" "$state"; then
  fail 'desktop lyrics start a process or a timer'
fi
if grep -nE '"#[0-9a-fA-F]{3,8}"' "$window" "$content" "$state"; then
  fail 'desktop lyrics QML contains a hardcoded color'
fi

test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
state_file="$test_root/state/hyprland-desktop/desktop-lyrics.json"

menu_ticked() {
  local rows
  rows=$(XDG_STATE_HOME="$test_root/state" "$lmenu" --dry-run style)
  awk -F '\t' '$4 == "style.lyrics" { found = 1; exit($3 == "✓" ? 0 : 1) } END { if (!found) exit 2 }' <<<"$rows"
}

menu_ticked || fail 'lmenu does not tick Desktop lyrics before any state is saved'

# run_smoke <label> [VAR=value...]: run the smoke with extra environment.
run_smoke() {
  local label=$1 smoke_log="$test_root/smoke-$1.log"
  shift
  env "$@" DBUS_SESSION_BUS_ADDRESS="unix:path=$test_root/no-bus" \
    HOME="$test_root" XDG_STATE_HOME="$test_root/state" QT_QPA_PLATFORM=offscreen \
    timeout 30 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: Desktop lyrics' "$smoke_log" \
    || { sed -n '1,120p' "$smoke_log" >&2; fail "DesktopLyricsSmoke.qml ($label) did not report success"; }
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail "DesktopLyricsSmoke.qml ($label) reported a failing assertion"
  fi
  printf 'ok: DesktopLyricsSmoke.qml %s (%s assertions)\n' "$label" "$(grep -c 'ok   ' "$smoke_log" || true)"
}

if command -v quickshell >/dev/null 2>&1; then
  run_smoke fresh
  test -f "$state_file" || fail 'the smoke toggle did not save the state file'
  # A restart with the saved "off" must see it before the shell builds the
  # widget, or LyricsState loads and starts lyric lookups.
  run_smoke saved-off DESKTOP_LYRICS_SMOKE_SAVED_OFF=1
else
  printf 'skip: quickshell is not installed, DesktopLyricsSmoke.qml not run\n'
  mkdir -p "${state_file%/*}"
  printf '{\n    "enabled": false\n}\n' >"$state_file"
fi

# Whatever Quickshell wrote after the toggle, the menu guard must read it as off.
if menu_ticked; then
  cat "$state_file" >&2
  fail 'lmenu still ticks Desktop lyrics after it was turned off'
fi

printf 'ok: desktop lyrics static and menu checks\n'
