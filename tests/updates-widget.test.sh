#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
state="$repo_root/quickshell/.config/quickshell/UpdatesState.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# pollTimer.restart() is called from both onExited handlers. With
# triggeredOnStart the restart fired the timer immediately, so every finished
# check started the next one and the AUR was queried until it returned 429.
# Kept as a text check: a QML Timer property the node fixtures cannot exercise.
! grep -Eq '^\s*triggeredOnStart:\s*true' "$state" ||
  fail 'poll timer fires on start, so restarting it re-runs the check immediately'

node "$repo_root/tests/updates-widget.logic.test.js" "$state"

# The workspace rule must not capture unrelated applications with this title.
for rules in "$repo_root/hypr/.config/hypr/conf/window_rules.lua" \
             "$repo_root/hypr/.config/hypr/conf/windows-rules.conf"; do
  grep -F 'title' "$rules" | grep -F 'System Update' | grep -Fq 'class' ||
    fail 'updater workspace rule matches unrelated application titles'
done

printf 'updates widget: ok\n'
