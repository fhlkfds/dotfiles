#!/usr/bin/env bash
# Exercise Super+Q with stand-in menu/compositor objects, never live windows.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d -t close-window-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

python3 - "$repo_root" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
lua = (root / "hypr/.config/hypr/conf/keybindings.lua").read_text()
conf = (root / "hypr/.config/hypr/conf/keybinding.conf").read_text()
bar = (root / "quickshell/.config/quickshell/Bar.qml").read_text()
shortcut = (root / "quickshell/.config/quickshell/CloseWindowShortcut.qml").read_text()
assert 'shell(mod .. " + Q", "close window", "close-window")' in lua, \
    "Super+Q bypasses the shell and can close the underlying window"
assert 'bindd = $mainMod, Q, close window, global, quickshell:close-window' in conf
assert 'CloseWindowShortcut {}' in bar
assert 'name: "close-window"' in shortcut and 'onPressed: closeWindow()' in shortcut
print("ok: Lua and compatibility bindings route Super+Q to the resident shell")
PY

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'skip: quickshell not installed\n'
  exit 0
fi

QT_QPA_PLATFORM=offscreen timeout 30 quickshell -p \
  "$repo_root/quickshell/.config/quickshell/CloseWindowSmoke.qml" >"$test_root/smoke.log" 2>&1 || {
  cat "$test_root/smoke.log" >&2
  fail 'close-window smoke did not run'
}
cat "$test_root/smoke.log"
if grep -Fq 'FAIL' "$test_root/smoke.log"; then
  fail 'close-window smoke reported a failing assertion'
fi
grep -Fq 'ok: close window shortcut' "$test_root/smoke.log" || fail 'close-window smoke did not finish'
