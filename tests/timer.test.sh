#!/usr/bin/env bash
# Countdown timer: the pure state machine under node, then TimerSmoke.qml
# (the real state, pill and panel content against a fake clock, a recording
# launcher and a fake do-not-disturb switch). Never starts notify-send or
# pw-play, and writes its state file under a temp dir.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
timer_qml=("$shell_dir/TimerState.qml" "$shell_dir/TimerIcon.qml" "$shell_dir/TimerPanel.qml"
  "$shell_dir/TimerPanelContent.qml" "$shell_dir/TimerSmoke.qml" "$shell_dir/timer/TimerConfig.qml")

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Colours come from Theme so a palette switch repaints the pill and panel.
if grep -nE '"#[0-9a-fA-F]{3,8}"' "${timer_qml[@]}"; then
  fail 'timer QML contains a hardcoded color'
fi

# The keypress path is a GlobalShortcut into the resident shell: no process
# starts until the timer rings, and the icon and panel never spawn anything.
if grep -nE 'Process|execDetached' "$shell_dir/TimerIcon.qml" "$shell_dir/TimerPanel.qml" \
    "$shell_dir/TimerPanelContent.qml"; then
  fail 'timer pill or panel spawns a process'
fi
grep -Fq 'GlobalShortcut { name: "timer"' "$shell_dir/Bar.qml" || fail 'Bar.qml has no timer GlobalShortcut'
grep -Fq 'shell(mod .. " + ALT + Z", "timer", "timer")' "$repo_root/hypr/.config/hypr/conf/keybindings.lua" \
  || fail 'keybindings.lua does not bind SUPER+ALT+Z to the timer'
printf 'ok: timer static checks\n'

python3 -m json.tool "$shell_dir/timer/config.json" >/dev/null

if command -v node >/dev/null 2>&1; then
  node "$repo_root/tests/timer.logic.test.js" "$shell_dir/timer/TimerLogic.js"
else
  printf 'skip: node is not installed, timer logic not run\n'
fi

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'skip: quickshell not installed, TimerSmoke.qml not run\n'
  exit 0
fi

test_root=$(mktemp -d -t timer-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
log="$test_root/smoke.log"
HOME="$test_root" XDG_STATE_HOME="$test_root/state" TIMER_STATE_FILE="$test_root/state/timer.json" \
  QT_QPA_PLATFORM=offscreen timeout 30 quickshell -p "$shell_dir/TimerSmoke.qml" >"$log" 2>&1 || true

if grep -Fq 'FAIL' "$log"; then
  grep -F 'FAIL' "$log" >&2
  fail 'TimerSmoke.qml reported a failing assertion'
fi
grep -Fq 'ok: timer smoke' "$log" || { sed -n '1,80p' "$log" >&2; fail 'TimerSmoke.qml did not report success'; }
printf 'ok: TimerSmoke.qml (%s assertions)\n' "$(grep -c 'ok   ' "$log" || true)"
