#!/usr/bin/env bash
set -euo pipefail

# notificationctl reaches the notification server over Quickshell IPC. A shell
# started with -p from another checkout is not the default config, so the plain
# IPC call finds nothing and notificationctl must fall back to its pid.

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/hypr/.local/bin/notificationctl"
test_root=$(mktemp -d -t notificationctl-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || { printf 'skip: python3 not installed\n'; exit 0; }

# The stub logs each call. FIXTURE_DEFAULT=1 means a shell runs from the
# default config; FIXTURE_LIST is what `list --all --json` prints.
cat >"$test_root/quickshell" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FIXTURE_LOG"
case "$*" in
  'list --all --json') printf '%s\n' "$FIXTURE_LIST" ;;
  'ipc call notifications '*)
    if [[ ${FIXTURE_DEFAULT:-0} == 1 ]]; then
      printf '%s\n' '{"available":true,"dnd":true,"visible":0,"history":0}'
    else
      printf 'No running instances for "%s"\n' "$HOME/.config/quickshell/shell.qml"
      exit 255
    fi ;;
  'ipc --pid 300 call notifications statusJson')
    printf '%s\n' '{"available":true,"dnd":false,"visible":2,"history":5}' ;;
  'ipc --pid 300 call notifications toggleDnd') printf 'toggled\n' ;;
  *) printf 'unexpected: %s\n' "$*" >&2; exit 3 ;;
esac
STUB
chmod +x "$test_root/quickshell"

export NOTIFICATIONCTL_QUICKSHELL="$test_root/quickshell"
export XDG_STATE_HOME="$test_root/state"
export FIXTURE_LOG="$test_root/calls"
# pid 300 is the newest full shell; 400 is newer but a smoke test, 200 older.
export FIXTURE_LIST='[
  {"pid": 200, "launch_time": "2026-10-29T10:00:00", "config_path": "/home/u/dotfiles/quickshell/.config/quickshell/shell.qml"},
  {"pid": 300, "launch_time": "2026-10-29T16:40:59", "config_path": "/wt/quickshell/.config/quickshell/shell.qml"},
  {"pid": 400, "launch_time": "2026-10-29T16:50:00", "config_path": "/wt/quickshell/.config/quickshell/BatterySmoke.qml"}
]'

# Default shell running: one IPC call, no fallback.
: >"$FIXTURE_LOG"
out=$(FIXTURE_DEFAULT=1 "$script" status --json) || fail "status failed with a default shell"
[[ $out == *'"dnd":true'* ]] || fail "default shell status not passed through: $out"
[[ $(wc -l <"$FIXTURE_LOG") -eq 1 ]] || fail "default shell made extra calls: $(cat "$FIXTURE_LOG")"

# Shell from another checkout: status reports it available through its pid.
: >"$FIXTURE_LOG"
out=$("$script" status --json) || fail "status failed for a shell outside the default config"
[[ $out == *'"available":true'* && $out == *'"visible":2'* ]] || fail "fallback status wrong: $out"
grep -Fxq 'ipc --pid 300 call notifications statusJson' "$FIXTURE_LOG" \
  || fail "fallback did not pick the newest full shell: $(cat "$FIXTURE_LOG")"

# Actions take the same path.
out=$("$script" dnd-toggle) || fail "dnd-toggle failed through the fallback"
[[ $out == toggled ]] || fail "dnd-toggle output wrong: $out"

# Only smoke instances running: no shell to reach, status stays unavailable.
: >"$FIXTURE_LOG"
if out=$(FIXTURE_LIST='[{"pid": 400, "launch_time": "x", "config_path": "/wt/XSmoke.qml"}]' "$script" status --json); then
  fail "status succeeded with only a smoke instance"
fi
[[ $out == *'"available":false'* ]] || fail "smoke-only status not unavailable: $out"
! grep -Fq -- '--pid' "$FIXTURE_LOG" || fail "smoke instance was used: $(cat "$FIXTURE_LOG")"

# Broken list output must not crash.
if out=$(FIXTURE_LIST='not json' "$script" status --json); then
  fail "status succeeded with unreadable instance list"
fi
[[ $out == *'"available":false'* ]] || fail "unreadable list status wrong: $out"

printf 'ok: notificationctl\n'
