#!/usr/bin/env bash
# The bar is the desktop's only tray host: if SystemTrayWidget leaves the bar,
# every app (Hermes Chat, nm-applet) silently loses its tray icon.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
bar="$shell_dir/Bar.qml"
shell_qml="$shell_dir/shell.qml"
module="$shell_dir/SystemTrayWidget.qml"
smoke="$shell_dir/SystemTraySmoke.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# The tray must sit in the right-hand island and get the bar window, which its
# menus open against.
awk '/id: trayIsland/ { inside = 1 } inside && /^        }/ { exit } inside' "$bar" \
  | grep -Eq 'SystemTrayWidget \{ parentWindow: panel;' \
  || fail 'SystemTrayWidget is not in the trayIsland of Bar.qml'

# Tray menus are platform menus, which need Quickshell in QApplication mode.
# Quickshell reads pragmas only before the first import.
awk '/^import / { exit } /^\/\/@ pragma UseQApplication$/ { found = 1 } END { exit !found }' \
  "$shell_qml" || fail 'shell.qml lacks //@ pragma UseQApplication before its imports'

# Tray icons are image URLs already; wrapping them again breaks themed icons.
if grep -nE 'iconPath\(' "$module"; then
  fail 'SystemTrayWidget wraps tray icon URLs with Quickshell.iconPath'
fi

# Colours must come from Theme so a palette switch repaints the module.
if grep -nE '"#[0-9a-fA-F]{3,8}"' "$module" "$smoke"; then
  fail 'system tray QML contains a hardcoded color'
fi

if command -v quickshell >/dev/null 2>&1; then
  test_root=$(mktemp -d)
  trap 'rm -rf -- "$test_root"' EXIT
  smoke_log="$test_root/smoke.log"
  HOME="$test_root" XDG_STATE_HOME="$test_root/state" QT_QPA_PLATFORM=offscreen \
    timeout 30 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: system tray smoke' "$smoke_log" \
    || { sed -n '1,60p' "$smoke_log" >&2; fail 'SystemTraySmoke.qml did not report success'; }
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'SystemTraySmoke.qml reported a failing assertion'
  fi
  printf 'ok: SystemTraySmoke.qml (%s assertions)\n' "$(grep -c 'ok   ' "$smoke_log" || true)"
else
  printf 'skip: quickshell is not installed, SystemTraySmoke.qml not run\n'
fi

printf 'ok: system tray static checks\n'
