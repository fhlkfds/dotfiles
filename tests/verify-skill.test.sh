#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
verify="$repo_root/.claude/skills/verify/bin/verify"
test_root=$(mktemp -d -t verify-skill-test.XXXXXX)
cache_home=${XDG_CACHE_HOME:-$HOME/.cache}
mkdir -p "$cache_home"
runs=$(mktemp -d -p "$cache_home" verify-skill-test.XXXXXX)
trap 'rm -rf -- "$test_root" "$runs"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_verify() { VERIFY_ROOT="$runs" "$verify" "$@"; }

"$verify" --help >/dev/null || fail '--help did not exit 0'
status=0; "$verify" bogus >/dev/null 2>&1 || status=$?
[[ $status == 2 ]] || fail "an unknown command exited $status, not 2"
status=0; run_verify run --label x >/dev/null 2>&1 || status=$?
[[ $status == 2 ]] || fail "run without a command exited $status, not 2"
status=0; VERIFY_ROOT=/tmp/verify-skill-test "$verify" launch >"$test_root/tmp-root.out" 2>&1 || status=$?
if [[ $status != 2 ]] || ! grep -Fq 'must not be under /tmp' "$test_root/tmp-root.out"; then
  fail 'a VERIFY_ROOT under /tmp was not refused'
fi

launch_path=$PATH
if ! command -v bwrap >/dev/null 2>&1; then
  mkdir -p "$test_root/bin"
  printf '#!/usr/bin/env sh\nexit 1\n' >"$test_root/bin/bwrap"
  chmod +x "$test_root/bin/bwrap"
  launch_path="$test_root/bin:$PATH"
fi
PATH="$launch_path" run_verify launch >"$test_root/launch.out" || fail 'launch failed'
grep -q '^ready: run ' "$test_root/launch.out" || fail 'launch did not print ready'
run_id=$(<"$runs/current")
sandbox="$runs/$run_id/sandbox"
evidence="$runs/$run_id/evidence"

[[ -x $sandbox/bin/hyprctl && -x $sandbox/bin/stow && -x $sandbox/bin/theme ]] \
  || fail 'launch did not install the stand-ins'
[[ ! -e $sandbox/bin/rofi ]] || fail 'rofi must stay real: theme validate parses with it'
[[ $(stat -c %a "$sandbox/runtime") == 700 ]] || fail 'the sandbox runtime dir is not private'
python3 -c 'import json, sys; assert json.load(open(sys.argv[1]))["colors"]["accent"]' \
  "$sandbox/home/.config/hypr/themes/.active/theme.json" \
  || fail 'launch did not seed a rendered theme.json'
[[ $(readlink "$sandbox/home/.local/bin/lmenu") == "$repo_root/menu/.local/bin/lmenu" ]] \
  || fail 'the sandbox home .local/bin/lmenu does not point at this checkout'
[[ $(readlink "$sandbox/home/.local/bin/theme") == "$sandbox/bin/theme" ]] \
  || fail 'the sandbox home .local/bin/theme does not go through the theme gate'

calls="$test_root/calls.log"
status=0; VERIFY_CALLS="$calls" "$sandbox/bin/hyprctl" eval 'a b' || status=$?
[[ $status == 1 ]] || fail "the hyprctl stand-in exited $status, not 1"
VERIFY_CALLS="$calls" "$sandbox/bin/notify-send" hi || fail 'the notify-send stand-in did not exit 0'
[[ $(cut -f2- "$calls" | head -1) == $'hyprctl\teval\ta\\ b' ]] \
  || fail "the stand-in logged the wrong line: $(head -1 "$calls")"

[[ $(VERIFY_CALLS="$calls" "$sandbox/bin/theme" current) == tokyo-night ]] \
  || fail 'theme current is not the run palette'
[[ $(VERIFY_CALLS="$calls" "$sandbox/bin/theme" mode) == dark ]] \
  || fail 'theme mode is not the run palette mode'
status=0; VERIFY_CALLS="$calls" "$sandbox/bin/theme" set nord 2>"$test_root/set.err" || status=$?
if [[ $status != 1 ]] || ! grep -Fq 'refused in the sandbox' "$test_root/set.err"; then
  fail 'the theme gate did not refuse theme set'
fi
grep -q $'\ttheme\tset\tnord$' "$calls" || fail 'the refused theme set was not logged'

mkdir -p "$evidence/01-kept" && printf 'proof\n' >"$evidence/01-kept/stdout.txt"
run_verify cleanup >/dev/null || fail 'cleanup failed'
[[ ! -e $sandbox ]] || fail 'cleanup left the sandbox'
[[ $(<"$evidence/01-kept/stdout.txt") == proof ]] || fail 'cleanup removed evidence'
[[ -f $runs/$run_id/CLEANED ]] || fail 'cleanup did not mark the run'
status=0; run_verify run -- true >/dev/null 2>&1 || status=$?
[[ $status != 0 ]] || fail 'a cleaned run accepted a command'
printf 'ok: verify launch layout, stand-ins, theme gate and cleanup\n'

in_container=0
[[ -f /.dockerenv || -f /run/.containerenv ]] && in_container=1
if ! command -v bwrap >/dev/null 2>&1; then
  if ((in_container)); then
    printf 'skip: bwrap is not installed in this docker container; sandbox checks not run\n'
  else
    printf 'skip: bwrap is not installed; sandbox checks not run\n'
  fi
  exit 0
fi
if ! bwrap --dev-bind / / --unshare-net --unshare-pid --proc /proc true 2>/dev/null; then
  if ((in_container)); then
    printf 'skip: this docker container blocks the namespaces bwrap needs; sandbox checks not run\n'
  else
    printf 'skip: bwrap cannot create namespaces on this host; sandbox checks not run\n'
  fi
  exit 0
fi

run_verify launch >/dev/null || fail 'second launch failed'
run_id=$(<"$runs/current")
evidence="$runs/$run_id/evidence"
run_verify doctor >"$test_root/doctor.out" || { cat "$test_root/doctor.out" >&2; fail 'doctor said not safe'; }
for want in mounts-readonly home-readonly home-hidden repo-readonly runtime-private \
            host-sockets-hidden system-bus-hidden network-down docker-hidden hyprctl-stubbed \
            session-env-clear; do
  grep -qx "ok    sandbox: $want" "$test_root/doctor.out" || fail "doctor did not prove $want"
done

socket_dir=$(mktemp -d -p "$cache_home" verify-skill-socket.XXXXXX)
trap 'rm -rf -- "$test_root" "$runs" "$socket_dir"' EXIT
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$socket_dir/live.sock"
status=0
# shellcheck disable=SC2016
run_verify run --label probe --env REAL_HOME="$HOME" --env SOCKET="$socket_dir/live.sock" -- bash -c \
  'hyprctl binds -j; [[ -S $SOCKET ]] && echo host-socket-visible; touch "$HOME/made"; touch "$REAL_HOME/.verify-skill-test"' \
  >/dev/null || status=$?
[[ $status == 1 ]] || fail "the probe exited $status, not 1"
[[ ! -e $HOME/.verify-skill-test ]] || { rm -f -- "$HOME/.verify-skill-test"; fail 'the sandbox wrote to the real home'; }
probe="$evidence/01-probe"
grep -q host-socket-visible "$probe/stdout.txt" && fail 'the sandbox could see a socket under the real home'
grep -q $'\thyprctl\tbinds\t-j$' "$probe/calls.log" || fail 'calls.log missed hyprctl'
grep -qx $'A\thome/made' "$probe/fs-changes.txt" || fail 'fs-changes.txt missed the sandbox write'
grep -Fq 'Read-only file system' "$probe/blocked.txt" || fail 'blocked.txt missed the real-home write'
[[ $(<"$probe/exit-code") == 1 ]] || fail 'exit-code is wrong'
grep -Fq 'FAIL (exit 1)  01-probe' "$evidence/INDEX" || fail 'INDEX missed the verdict'

run_verify run --label dry -- "$repo_root/hypr/.config/hypr/scripts/night-light.sh" --dry-run on \
  >/dev/null || fail 'night-light --dry-run failed in the sandbox'
[[ ! -s $evidence/02-dry/calls.log ]] || fail 'night-light --dry-run called a stand-in'
grep -q 'night-light-shader' "$evidence/02-dry/fs-changes.txt" && fail 'night-light --dry-run wrote state'
printf 'ok: verify sandbox isolation and evidence\n'

if command -v quickshell >/dev/null 2>&1; then
  run_verify shot battery-panel >"$test_root/shot.out" || { cat "$test_root/shot.out" >&2; fail 'the battery panel shot failed'; }
  grep -Fq 'ok   clicking the bar icon opens the panel' "$evidence/03-shot-battery-panel/checks.txt" \
    || fail 'the shot did not open the panel by clicking'
  printf 'ok: verify battery panel shot (%s PNGs)\n' "$(find "$evidence/03-shot-battery-panel" -name '*.png' | wc -l)"
else
  printf 'skip: quickshell is not installed, battery panel shot not run\n'
fi
run_verify cleanup >/dev/null
[[ -f $evidence/01-probe/calls.log ]] || fail 'cleanup removed sandbox evidence'
printf 'ok: verify cleanup keeps evidence\n'
