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
launcher="$shell_dir/AppLauncher.qml"
logic="$shell_dir/tray/TrayAppsLogic.js"
logic_test="$repo_root/tests/system-tray.logic.test.js"

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

# Pinned apps draw in the launcher, so the tray must be told which they are,
# or Spotify shows twice.
awk '/id: trayIsland/ { inside = 1 } inside && /^        }/ { exit } inside' "$bar" \
  | grep -Eq 'SystemTrayWidget \{[^}]*pinnedApps: appLauncher\.apps' \
  || fail 'SystemTrayWidget is not given the launcher'"'"'s pinned apps'
awk '/id: trayIsland/ { inside = 1 } inside && /^        }/ { exit } inside' "$bar" \
  | grep -Eq 'AppLauncher \{ id: appLauncher; parentWindow: panel;' \
  || fail 'AppLauncher lacks its id or the bar window for tray menus'

# A click on an app icon is the hot path: focusing is an in-process dispatch,
# never a spawned process. Only a launch may spawn.
if grep -nE '\bProcess \{|SplitParser|Timer \{' "$module" "$launcher"; then
  fail 'tray or launcher spawns a process object or polls on the click path'
fi
[[ $(grep -c 'execDetached' "$launcher") == 1 ]] ||
  fail 'AppLauncher should spawn only in its launch fallback'

if command -v node >/dev/null 2>&1; then
  node "$logic_test" "$logic" >/dev/null || { node "$logic_test" "$logic" >&2 || true; fail 'tray app logic test failed'; }
  printf 'ok: tray app logic\n'
else
  printf 'skip: node is not installed, tray app logic not run\n'
fi

# Colours must come from Theme so a palette switch repaints the module.
if grep -nE '"#[0-9a-fA-F]{3,8}"' "$module" "$smoke" "$launcher"; then
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
