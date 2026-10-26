#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir="$repo_root/quickshell/.config/quickshell"
logic="$shell_dir/workspaces/WorkspacesLogic.js"
logic_test="$repo_root/tests/workspaces-module.logic.test.js"
smoke="$shell_dir/WorkspacesSmoke.qml"
module="$shell_dir/WorkspacesModule.qml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Badges come from live workspaces; a hard-coded per-id list is how workspaces
# 9, 11 and 17 went missing, and icons are gone in favour of numbers.
if grep -Eq 'slots|glyph|svg|DesktopEntries|iconPath' "$module"; then
  fail 'WorkspacesModule still carries a fixed icon list or icon lookup'
fi

# The click path must stay a plain dispatch: no process, no polling.
if grep -nE 'Process|SplitParser|Timer|execDetached' "$module"; then
  fail 'WorkspacesModule spawns processes or polls'
fi

if command -v node >/dev/null 2>&1; then
  node "$logic_test" "$logic" || fail 'workspaces logic test failed'
else
  printf 'skip: node is not installed, workspaces logic not run\n'
fi

if command -v quickshell >/dev/null 2>&1; then
  test_root=$(mktemp -d)
  trap 'rm -rf -- "$test_root"' EXIT
  smoke_log="$test_root/smoke.log"
  HOME="$test_root" XDG_STATE_HOME="$test_root/state" QT_QPA_PLATFORM=offscreen \
    timeout 30 quickshell -p "$smoke" >"$smoke_log" 2>&1 || true
  grep -Fq 'ok: workspaces smoke' "$smoke_log" \
    || { sed -n '1,60p' "$smoke_log" >&2; fail 'WorkspacesSmoke.qml did not report success'; }
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'WorkspacesSmoke.qml reported a failing assertion'
  fi
  printf 'ok: WorkspacesSmoke.qml (%s assertions)\n' "$(grep -c 'ok   ' "$smoke_log" || true)"
else
  printf 'skip: quickshell is not installed, WorkspacesSmoke.qml not run\n'
fi
