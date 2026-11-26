#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/herdr/.local/bin/herdr-up"
test_root=$(mktemp -d -t herdr-up.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || { printf 'skip: jq not installed\n'; exit 0; }

# A stand-in for the Herdr socket API: reads canned JSON, records every call
# that changes something, and reports a pane busy once a command ran in it.
mkdir -p "$test_root/bin"
cat >"$test_root/bin/herdr" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
d=$HERDR_STUB_DIR
if [[ ${1:-} == --session ]]; then
  printf '%s\n' "$2" >>"$d/sessions"
  shift 2
fi
case "${1:-} ${2:-}" in
  "workspace list") cat "$d/workspaces.json" ;;
  "tab list") cat "$d/tabs.json" ;;
  "pane list") cat "$d/panes.json" ;;
  "pane process-info")
    group=1
    [[ -e "$d/busy/$4" ]] && group=2
    if [[ -s "$d/starting/$4" ]]; then
      left=$(<"$d/starting/$4")
      ((left > 0)) && group=2
      echo $((left - 1)) >"$d/starting/$4"
    fi
    printf '{"result":{"process_info":{"foreground_process_group_id":%s,"shell_pid":1}}}\n' "$group" ;;
  "tab create")
    printf '%s\n' "$*" >>"$d/calls"
    printf '{"result":{"root_pane":{"pane_id":"w1:p99"}}}\n' ;;
  "pane run")
    printf '%s\n' "$*" >>"$d/calls"
    touch "$d/busy/$3" ;;
  " ") printf 'attach\n' >>"$d/calls" ;;
  *) printf 'unexpected herdr call: %s\n' "$*" >&2; exit 3 ;;
esac
SH
chmod +x "$test_root/bin/herdr"

# Seconds since the pane's shell started; long-running unless a case says so.
cat >"$test_root/bin/ps" <<'SH'
#!/usr/bin/env bash
cat "$HERDR_STUB_DIR/shell-age"
SH
chmod +x "$test_root/bin/ps"

# Herdr as it comes back after a reboot: both SSH tabs are idle local shells.
reset_session() {
  stub=$test_root/stub
  rm -rf -- "$stub"
  mkdir -p "$stub/busy" "$stub/starting"
  echo 3600 >"$stub/shell-age"
  : >"$stub/calls"
  printf '{"result":{"workspaces":[{"workspace_id":"w1"}]}}\n' >"$stub/workspaces.json"
  cat >"$stub/tabs.json" <<'JSON'
{"result":{"tabs":[
  {"tab_id":"w1:t4","label":"Kelper"},
  {"tab_id":"w1:t7","label":"hubble"},
  {"tab_id":"w1:t8","label":"Hermes"}]}}
JSON
  cat >"$stub/panes.json" <<'JSON'
{"result":{"panes":[
  {"pane_id":"w1:p4","tab_id":"w1:t4"},
  {"pane_id":"w1:p7","tab_id":"w1:t7"},
  {"pane_id":"w1:p9","tab_id":"w1:t8"}]}}
JSON
}

herdr_up() {
  HERDR_STUB_DIR=$stub PATH="$test_root/bin:$PATH" HERDR_UP_STATE_DIR="$test_root/state" \
    HERDR_UP_WAIT_SECONDS=${HERDR_UP_WAIT_SECONDS:-2} "$script" "$@"
}

expect_calls() {
  local expected actual
  expected=$(printf '%s\n' "$@")
  actual=$(cat "$stub/calls")
  [[ $actual == "$expected" ]] || fail "unexpected herdr calls
expected:
$expected
got:
$actual"
}

bash -n "$script"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$script" "${BASH_SOURCE[0]}"
else
  printf 'skip: shellcheck not installed\n'
fi

reset_session
herdr_up --no-attach >/dev/null
expect_calls 'pane run w1:p7 sshpersist hubble' 'pane run w1:p9 sshpersist hermes'

output=$(herdr_up --no-attach)
expect_calls 'pane run w1:p7 sshpersist hubble' 'pane run w1:p9 sshpersist hermes'
[[ $output == *'hubble: busy, left alone'* ]] || fail "a second run did not leave connected tabs alone: $output"

reset_session
touch "$stub/busy/w1:p7"
started=$SECONDS
herdr_up --no-attach >/dev/null
expect_calls 'pane run w1:p9 sshpersist hermes'
((SECONDS - started < 2)) || fail 'waited on a tab that has been busy for an hour'

reset_session
echo 1 >"$stub/shell-age"
echo 3 >"$stub/starting/w1:p7"
herdr_up --no-attach >/dev/null
expect_calls 'pane run w1:p7 sshpersist hubble' 'pane run w1:p9 sshpersist hermes'

reset_session
echo 1 >"$stub/shell-age"
touch "$stub/busy/w1:p7"
HERDR_UP_WAIT_SECONDS=1 herdr_up --no-attach >/dev/null
expect_calls 'pane run w1:p9 sshpersist hermes'

reset_session
jq '.result.tabs |= map(select(.label != "Hermes"))' "$stub/tabs.json" >"$stub/tabs.tmp"
mv "$stub/tabs.tmp" "$stub/tabs.json"
herdr_up --no-attach >/dev/null
expect_calls 'pane run w1:p7 sshpersist hubble' \
  "tab create --workspace w1 --label Hermes --cwd $HOME --no-focus" \
  'pane run w1:p99 sshpersist hermes'

reset_session
output=$(herdr_up --dry-run)
expect_calls
[[ $output == *'+ pane run w1:p7 sshpersist hubble'* ]] || fail "dry run did not show the hubble connect: $output"

reset_session
HERDR_UP_TARGETS='hubble=hubble,bad=x;id,=hermes,nohost' herdr_up --no-attach >/dev/null 2>"$test_root/err"
expect_calls 'pane run w1:p7 sshpersist hubble'
(($(grep -c 'skipping bad target' "$test_root/err") == 3)) || fail "unsafe targets were not all reported: $(cat "$test_root/err")"

reset_session
printf '{"result":{"workspaces":[]}}\n' >"$stub/workspaces.json"
if HERDR_UP_WAIT_SECONDS=0 herdr_up --no-attach >/dev/null 2>&1; then
  fail 'succeeded with no Herdr workspace'
fi
expect_calls

reset_session
HERDR_UP_SESSION=lab herdr_up
for _ in $(seq 50); do
  (($(wc -l <"$stub/calls") >= 3)) && break
  sleep 0.1
done
sort -o "$stub/calls" "$stub/calls"
expect_calls 'attach' 'pane run w1:p7 sshpersist hubble' 'pane run w1:p9 sshpersist hermes'
grep -qvx lab "$stub/sessions" && fail 'a Herdr call ignored HERDR_UP_SESSION'
[[ -s $test_root/state/last-run.log ]] || fail 'the background run left no log'

printf 'ok: herdr-up fixtures\n'
