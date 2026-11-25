#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
hook="$repo_root/ai/.local/bin/agent-permission-hook"
test_root=$(mktemp -d -t agent-permission-hook-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null || { printf 'skip: jq not installed\n'; exit 0; }

mkdir -p "$test_root/bin"
cat >"$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf 'x\n' >>"$FAKE_DIR/notify-calls"
printf '%s\0' "$@" >"$FAKE_DIR/argv"
printf '%s' "${LD_LIBRARY_PATH-<unset>}" >"$FAKE_DIR/ld"
[[ ${FAKE_NOTIFY_CLICK:-} != fail ]] || exit 1
printf '42\n'
case ${FAKE_NOTIFY_CLICK:-dismiss} in
  allow|deny) printf '%s\n' "$FAKE_NOTIFY_CLICK" ;;
  hang) exec sleep 60 ;;
  weird) printf 'rm -rf\n' ;;
esac
SH
cat >"$test_root/bin/gdbus" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_DIR/gdbus"
SH
chmod +x "$test_root/bin/notify-send" "$test_root/bin/gdbus"

export AGENT_PERMISSION_NOTIFY_SEND="$test_root/bin/notify-send"
export AGENT_PERMISSION_GDBUS="$test_root/bin/gdbus"

allow='{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
deny='{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from the desktop notification."}}}'

# run <click> <payload> <hook args...>: sets out and status, resets the fakes.
run() {
  local click=$1 payload=$2
  shift 2
  export FAKE_DIR="$test_root/fake"
  rm -rf "$FAKE_DIR"
  mkdir -p "$FAKE_DIR"
  status=0
  out=$(FAKE_NOTIFY_CLICK=$click PATH="$test_root/bin:$PATH" "$hook" "$@" <<<"$payload" 2>"$FAKE_DIR/stderr") || status=$?
}

payload_for() { # tool, tool_input json
  jq -cn --arg tool "$1" --argjson input "$2" \
    '{hook_event_name: "PermissionRequest", tool_name: $tool, tool_input: $input, cwd: "/tmp/p", session_id: "s"}'
}

read_argv() { mapfile -d '' -t argv <"$FAKE_DIR/argv"; }
argv_index() { # index of the `--` separator
  local i
  for i in "${!argv[@]}"; do [[ ${argv[i]} == -- ]] && { printf '%s' "$i"; return; }; done
  fail 'no -- separator in notify-send argv'
}
no_notify() { [[ ! -e $FAKE_DIR/notify-calls ]] || fail "$1: notify-send was called"; }
check_json() { # name, got, want
  [[ $(jq -cS . <<<"$2") == "$(jq -cS . <<<"$3")" ]] || fail "$1: got '$2'"
}
pass() { printf 'ok   %s\n' "$1"; }

bash_payload=$(payload_for Bash '{"command":"touch /tmp/x"}')

run allow "$bash_payload" claude
[[ $status == 0 ]] || fail 'claude allow: exit status'
check_json 'claude allow' "$out" "$allow"
pass 'claude allow click'

run deny "$bash_payload" claude
check_json 'claude deny' "$out" "$deny"
pass 'claude deny click'

run allow "$bash_payload" codex
check_json 'codex allow' "$out" "$allow"
run deny "$bash_payload" codex
check_json 'codex deny' "$out" "$deny"
pass 'codex allow and deny'

start=$EPOCHREALTIME
run hang "$bash_payload" --timeout 1 claude
elapsed=$(( (${EPOCHREALTIME/./} - ${start/./}) / 1000 ))
[[ $status == 0 && -z $out ]] || fail 'timeout: expected empty stdout, exit 0'
grep -q 'CloseNotification 42' "$FAKE_DIR/gdbus" || fail 'timeout: card not closed'
((elapsed < 4000)) || fail "timeout: took ${elapsed} ms"
pass 'timeout answers nothing and closes the card'

run dismiss "$bash_payload" claude
[[ $status == 0 && -z $out ]] || fail 'dismiss: expected empty'
pass 'dismiss answers nothing'

run fail "$bash_payload" claude
[[ $status == 0 && -z $out ]] || fail 'notify-send failure: expected empty'
run weird "$bash_payload" claude
[[ $status == 0 && -z $out ]] || fail 'unexpected action: expected empty'
pass 'notify-send failure and unexpected action answer nothing'

export FAKE_DIR="$test_root/fake"
rm -rf "$FAKE_DIR"
mkdir -p "$FAKE_DIR"
printf '%s' "$bash_payload" >"$test_root/payload"
FAKE_NOTIFY_CLICK=hang PATH="$test_root/bin:$PATH" "$hook" claude <"$test_root/payload" >"$test_root/term-out" 2>/dev/null &
hook_pid=$!
for _ in $(seq 50); do [[ -s $FAKE_DIR/ld ]] && break; sleep 0.1; done
sleep 0.3
kill -TERM "$hook_pid"
start=$EPOCHREALTIME
status=0
wait "$hook_pid" || status=$?
elapsed=$(( (${EPOCHREALTIME/./} - ${start/./}) / 1000 ))
[[ $status == 0 && ! -s $test_root/term-out ]] || fail 'TERM: expected empty stdout, exit 0'
grep -q 'CloseNotification 42' "$FAKE_DIR/gdbus" || fail 'TERM: card not closed'
((elapsed < 1000)) || fail "TERM: took ${elapsed} ms to exit"
pass 'TERM closes the card and exits promptly'

command=$'-n <b>&</b> "q" '\''s'\'' $(touch /tmp/pwned) `x`\n  line two > out\\n'
payload=$(payload_for Bash "$(jq -cn --arg c "$command" '{command: $c}')")
run allow "$payload" claude
read_argv
i=$(argv_index)
[[ ${argv[i + 2]} == "$command"$'\n\nin /tmp/p' ]] || fail 'verbatim: body differs'
[[ ${argv[i + 1]} == 'Claude Code wants to run a command' ]] || fail 'verbatim: summary'
joined=$(printf '%s\n' "${argv[@]:0:i}")
for want in allow='Allow once' deny=Deny boolean:desktop-verbatim:true boolean:desktop-bypass-dnd:true 120000; do
  grep -qxF -- "$want" <<<"$joined" || fail "verbatim: missing $want"
done
first_action=$(grep -m1 -E '^(allow|deny)=' <<<"$joined")
[[ $first_action == deny=Deny ]] || fail "verbatim: Deny must be the first (filled) button, got $first_action"
pass 'body reaches notify-send verbatim after --'

payload=$(payload_for exec_command '{"command":["git","commit","-m","a b"]}')
run allow "$payload" codex
read_argv
i=$(argv_index)
want_command="'git' 'commit' '-m' 'a b'"$'\n\nin /tmp/p'
[[ ${argv[i + 2]} == "$want_command" ]] || fail "argv command: '${argv[i + 2]}'"
pass 'command array is joined'

payload=$(payload_for Edit '{"file_path":"/home/x/a.txt","old_string":"a","new_string":"b"}')
run allow "$payload" claude
read_argv
i=$(argv_index)
[[ ${argv[i + 1]} == 'Claude Code wants to edit a file' ]] || fail 'edit: summary'
[[ ${argv[i + 2]} == "/home/x/a.txt"$'\n\nin /tmp/p' ]] || fail 'edit: body'
payload=$(payload_for mcp__thing '{"a":1,"b":[2]}')
run allow "$payload" claude
read_argv
i=$(argv_index)
[[ ${argv[i + 1]} == 'Claude Code wants to use mcp__thing' ]] || fail 'unknown tool: summary'
jq -e '.a == 1 and .b == [2]' <<<"${argv[i + 2]%%$'\n\nin '*}" >/dev/null || fail 'unknown tool: JSON body'
pass 'edit shows the path, unknown tool shows JSON'

patch=$'*** Begin Patch\n*** Add File: /tmp/p/new.txt\n+hi\n*** End Patch'
run allow "$(payload_for apply_patch "$(jq -cn --arg c "$patch" '{command: $c}')")" codex
read_argv
i=$(argv_index)
[[ ${argv[i + 1]} == 'Codex wants to edit a file' ]] || fail 'apply_patch: summary'
[[ ${argv[i + 2]} == "$patch"$'\n\nin /tmp/p' ]] || fail "apply_patch: body '${argv[i + 2]}'"
pass 'codex apply_patch shows the whole patch'

run allow 'not json' claude
[[ $status == 0 && -z $out ]] || fail 'invalid JSON: expected empty'
no_notify 'invalid JSON'
run allow '{"hook_event_name":"PreToolUse","tool_name":"Bash"}' claude
[[ $status == 0 && -z $out ]] || fail 'wrong event: expected empty'
no_notify 'wrong event'
run allow '{"hook_event_name":"PermissionRequest"}' claude
[[ $status == 0 && -z $out ]] || fail 'missing tool: expected empty'
no_notify 'missing tool'
pass 'invalid input answers nothing and sends nothing'

AGENT_PERMISSION_MAX_BODY=100 run allow "$(payload_for Bash "$(jq -cn --arg c "$(head -c 300 /dev/zero | tr '\0' a)" '{command: $c}')")" claude
[[ $status == 0 && -z $out ]] || fail 'oversized: expected empty'
no_notify 'oversized'
[[ -s $FAKE_DIR/stderr ]] || fail 'oversized: expected a stderr note'
pass 'oversized body shows no card'

LD_LIBRARY_PATH=/nonexistent/lib run allow "$bash_payload" claude
[[ $(<"$FAKE_DIR/ld") == '<unset>' ]] || fail "LD_LIBRARY_PATH leaked: $(<"$FAKE_DIR/ld")"
pass 'notify-send does not see LD_LIBRARY_PATH'

for bad in "" "--bogus claude" "claude codex" "gemini" "--timeout claude" "--timeout 0 claude" "--timeout x claude"; do
  # shellcheck disable=SC2086
  run allow "$bash_payload" $bad
  [[ $status == 2 ]] || fail "bad args '$bad': exit $status"
done
AGENT_PERMISSION_TIMEOUT=abc run allow "$bash_payload" claude
[[ $status == 2 ]] || fail 'bad AGENT_PERMISSION_TIMEOUT'
no_notify 'bad args'
pass 'bad arguments exit 2'

run allow "$bash_payload" --dry-run claude
[[ $status == 0 ]] || fail 'dry-run: exit status'
no_notify 'dry-run'
grep -qF 'Claude Code wants to run a command' <<<"$out" || fail 'dry-run: summary'
grep -qF 'touch /tmp/x' <<<"$out" || fail 'dry-run: body'
grep -q 'desktop-verbatim' <<<"$out" || fail 'dry-run: argv'
grep -q 'behavior' <<<"$out" && fail 'dry-run: must not answer'
pass 'dry-run calls nothing'
