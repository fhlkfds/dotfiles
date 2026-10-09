#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
night_light="$repo_root/hypr/.config/hypr/scripts/night-light.sh"
test_root=$(mktemp -d -t night-light-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$test_root/bin"
export HOME="$test_root/home"
cat >"$test_root/bin/hyprctl-fixture" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 2 && $1 == eval ]] || exit 2
printf '%s\n' "$*" >>"$NIGHT_LIGHT_FIXTURE_CALLS"
if [[ -n ${NIGHT_LIGHT_FIXTURE_BLOCK:-} ]]; then
  exec {release_fd}<>"$NIGHT_LIGHT_FIXTURE_BLOCK/release"
  touch "$NIGHT_LIGHT_FIXTURE_BLOCK/entered"
  read -r -t 5 -u "$release_fd" _
fi
if [[ -n ${NIGHT_LIGHT_FIXTURE_LUA:-} ]]; then
  "$NIGHT_LIGHT_FIXTURE_LUA" "$NIGHT_LIGHT_FIXTURE_LUA_SCRIPT" "$2"
fi
printf '%s\n' "${NIGHT_LIGHT_FIXTURE_RESPONSE-ok}"
[[ ${NIGHT_LIGHT_FIXTURE_EXIT:-0} == 0 ]] || exit "$NIGHT_LIGHT_FIXTURE_EXIT"
printf '%s\n' "$*" >>"$NIGHT_LIGHT_FIXTURE_APPLIED"
SH
chmod +x "$test_root/bin/hyprctl-fixture"

export NIGHT_LIGHT_STATE_FILE="$test_root/state/night-light-shader"
export NIGHT_LIGHT_HYPRCTL="$test_root/bin/hyprctl-fixture"
export NIGHT_LIGHT_FIXTURE_CALLS="$test_root/calls"
export NIGHT_LIGHT_FIXTURE_APPLIED="$test_root/applied"
full_frames='general = { border_size = assert(hl.get_config("general.border_size")) }'
on_call="eval hl.config({ decoration = { screen_shader = [==[$HOME/.config/hypr/shaders/night-light.frag]==] }, $full_frames })"
off_call="eval hl.config({ decoration = { screen_shader = [==[]==] }, $full_frames })"

"$night_light" on
[[ -f "$NIGHT_LIGHT_STATE_FILE" ]] || fail 'on did not enable shader state'
[[ "$(<"$NIGHT_LIGHT_FIXTURE_CALLS")" == "$on_call" ]] || fail 'on did not apply the shader live'

: >"$NIGHT_LIGHT_FIXTURE_CALLS"
"$night_light" toggle
[[ ! -e "$NIGHT_LIGHT_STATE_FILE" ]] || fail 'toggle did not disable shader state'
[[ "$(<"$NIGHT_LIGHT_FIXTURE_CALLS")" == "$off_call" ]] || fail 'toggle off did not clear the shader live'

: >"$NIGHT_LIGHT_FIXTURE_CALLS"
"$night_light" toggle
[[ -f "$NIGHT_LIGHT_STATE_FILE" ]] || fail 'toggle did not enable shader state'
[[ "$(<"$NIGHT_LIGHT_FIXTURE_CALLS")" == "$on_call" ]] || fail 'toggle on did not apply the shader live'

[[ "$("$night_light" status)" == 'night-light: on (screen shader)' ]] ||
  fail 'status did not report enabled shader'

before=$(<"$NIGHT_LIGHT_STATE_FILE")
before_calls=$(<"$NIGHT_LIGHT_FIXTURE_CALLS")
dry_run_output=$("$night_light" --dry-run off)
after=$(<"$NIGHT_LIGHT_STATE_FILE")
[[ "$before" == "$after" ]] || fail 'dry-run changed shader state'
[[ "$dry_run_output" == *'disable shader state'* && "$dry_run_output" == *'screen_shader'* ]] ||
  fail 'dry-run did not describe state and shader actions'
"$night_light" --dry-run on >/dev/null
[[ "$(<"$NIGHT_LIGHT_FIXTURE_CALLS")" == "$before_calls" ]] || fail 'dry-run invoked hyprctl'

"$night_light" off
[[ ! -e "$NIGHT_LIGHT_STATE_FILE" ]] || fail 'off did not clear state'
[[ "$("$night_light" status)" == 'night-light: off' ]] || fail 'status did not report off'
"$night_light" --dry-run on >/dev/null
[[ ! -e "$NIGHT_LIGHT_STATE_FILE" ]] || fail 'dry-run on created state'
NIGHT_LIGHT_STATE_FILE="$test_root/dry-run/state" "$night_light" --dry-run on >/dev/null
[[ ! -e "$test_root/dry-run" ]] || fail 'dry-run created a state directory or lock'

# Application failures remain visible, while desired state persists for login.
for response in 'error: fixture Lua failure' ''; do
  for exit_code in 0 7; do
    for action in on off; do
      if NIGHT_LIGHT_FIXTURE_RESPONSE="$response" NIGHT_LIGHT_FIXTURE_EXIT="$exit_code" \
        "$night_light" "$action" >"$test_root/failure.out" 2>"$test_root/failure.err"; then
        fail "$action accepted an unsuccessful IPC response"
      fi
      [[ ! -s "$test_root/failure.out" ]] || fail 'failed apply printed success'
      grep -Fq 'night-light: could not apply shader:' "$test_root/failure.err" || fail 'missing failure diagnostic'
      if [[ -n "$response" ]]; then
        grep -Fq "$response" "$test_root/failure.err" || fail 'discarded the Hyprland error'
      fi
      if [[ "$action" == on ]]; then
        [[ -f "$NIGHT_LIGHT_STATE_FILE" ]] || fail 'failed on lost desired login state'
      else
        [[ ! -e "$NIGHT_LIGHT_STATE_FILE" ]] || fail 'failed off lost desired login state'
      fi
    done
  done
done
if NIGHT_LIGHT_FIXTURE_RESPONSE=ok NIGHT_LIGHT_FIXTURE_EXIT=7 \
  "$night_light" on >"$test_root/failure.out" 2>"$test_root/failure.err"; then
  fail 'on ignored a failing hyprctl exit code'
fi

# Evaluate the actual emitted Lua, including borderless/custom-border settings
# and paths containing spaces, quotes, and multiple Lua closing delimiters.
if command -v lua >/dev/null 2>&1; then
  export NIGHT_LIGHT_FIXTURE_LUA
  NIGHT_LIGHT_FIXTURE_LUA=$(command -v lua)
  export NIGHT_LIGHT_FIXTURE_LUA_SCRIPT="$test_root/check.lua"
  cat >"$NIGHT_LIGHT_FIXTURE_LUA_SCRIPT" <<'LUA'
local border = tonumber(os.getenv("NIGHT_LIGHT_FIXTURE_BORDER"))
local calls = 0
hl = {
  get_config = function(key)
    assert(key == "general.border_size")
    return border
  end,
  config = function(config)
    calls = calls + 1
    assert(config.general.border_size == border, "changed the current border")
    assert(config.decoration.screen_shader == os.getenv("NIGHT_LIGHT_FIXTURE_EXPECTED_SHADER"), "corrupted shader path")
    for key in pairs(config) do assert(key == "general" or key == "decoration") end
  end,
}
assert(load(arg[1]))()
assert(calls == 1, "expected one config update")
LUA
  for border in 0 2 20; do
    export NIGHT_LIGHT_FIXTURE_BORDER="$border"
    for fixture_home in "$test_root/home" "$test_root/home with 'quotes' and ]==] and ]===]"; do
      HOME="$fixture_home" NIGHT_LIGHT_FIXTURE_EXPECTED_SHADER="$fixture_home/.config/hypr/shaders/night-light.frag" \
        "$night_light" on >/dev/null
      NIGHT_LIGHT_FIXTURE_EXPECTED_SHADER='' "$night_light" off >/dev/null
    done
  done
  if NIGHT_LIGHT_FIXTURE_BORDER=missing "$night_light" on >/dev/null 2>"$test_root/lua-failure.err"; then
    fail 'missing border config silently skipped the redraw workaround'
  fi
  unset NIGHT_LIGHT_FIXTURE_LUA
else
  printf 'skip: lua is not installed; emitted Lua was not executed\n'
fi

# Hold the first toggle inside IPC while starting another. Both must finish
# with off persisted and applied last, and the second must wait for the first.
"$night_light" off >/dev/null
: >"$NIGHT_LIGHT_FIXTURE_CALLS"
: >"$NIGHT_LIGHT_FIXTURE_APPLIED"
python3 - "$night_light" "$test_root" "$on_call" "$off_call" <<'PY'
import os, pathlib, signal, subprocess, sys, time
script, root, on_call, off_call = sys.argv[1:]
block = pathlib.Path(root) / "block"
block.mkdir()
os.mkfifo(block / "release")
first = subprocess.Popen([script, "toggle"], env=dict(os.environ, NIGHT_LIGHT_FIXTURE_BLOCK=str(block)),
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
second = None
try:
    deadline = time.monotonic() + 5
    while not (block / "entered").exists():
        assert first.poll() is None and time.monotonic() < deadline, "first toggle did not reach IPC"
        time.sleep(0.01)
    second = subprocess.Popen([script, "toggle"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                              start_new_session=True)
    try:
        second.communicate(timeout=0.2)
    except subprocess.TimeoutExpired:
        pass
    else:
        raise AssertionError("second toggle did not wait for the first")
    with (block / "release").open("w") as release:
        release.write("continue\n")
    for process in (first, second):
        out, err = process.communicate(timeout=5)
        assert process.returncode == 0, (out, err)
    assert not pathlib.Path(os.environ["NIGHT_LIGHT_STATE_FILE"]).exists(), "overlapping toggles left state enabled"
    for name in ("NIGHT_LIGHT_FIXTURE_CALLS", "NIGHT_LIGHT_FIXTURE_APPLIED"):
        assert pathlib.Path(os.environ[name]).read_text().splitlines() == [on_call, off_call], name
finally:
    for process in (first, second):
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=5)
PY
grep -Fq 'reload' "$NIGHT_LIGHT_FIXTURE_CALLS" && fail 'night light still does a full Hyprland reload'

printf 'ok: night-light shader fixtures\n'
