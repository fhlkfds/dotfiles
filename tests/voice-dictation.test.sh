#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/hypr/.config/hypr/scripts/voice-dictation"
menu="$repo_root/menu/.config/lmenu/menu.jsonc"
lua="$repo_root/hypr/.config/hypr/conf/keybindings.lua"
legacy="$repo_root/hypr/.config/hypr/conf/keybinding.conf"
test_root=$(mktemp -d -t voice-dictation-test.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

mkdir -p "$test_root/bin" "$test_root/hyprvoice"
cat >"$test_root/bin/wpctl" <<'SH'
#!/usr/bin/env bash
[[ $1 == inspect ]] || exit 2
case $2 in
  @DEFAULT_AUDIO_SINK@)
    printf 'id 103, type PipeWire:Interface:Node\n  * device.id = "%s"\n' \
      "${VOICE_DICTATION_SINK_DEVICE_ID:-102}"
    ;;
  @DEFAULT_AUDIO_SOURCE@)
    cat <<'OUT'
id 50, type PipeWire:Interface:Node
  * node.name = "alsa_input.webcam"
OUT
    ;;
  *) exit 2 ;;
esac
SH
cat >"$test_root/bin/pw-dump" <<'SH'
#!/usr/bin/env bash
cat <<'JSON'
[{"type":"PipeWire:Interface:Node","info":{"props":{"media.class":"Audio/Source","node.name":"alsa_input.webcam","node.description":"Webcam","device.id":"50"}}},{"type":"PipeWire:Interface:Node","info":{"props":{"media.class":"Audio/Source","node.name":"bluez_input.airpods","node.description":"AirPods Pro","device.id":"102"}}}]
JSON
SH
# Toggling starts listening, then follows an optional delayed typing sequence.
cat >"$test_root/bin/hyprvoice" <<'SH'
#!/usr/bin/env bash
state=$(cat "$HYPRVOICE_STATE" 2>/dev/null || printf idle)
case $1 in
  status)
    [[ -z ${HYPRVOICE_HOLD:-} || $state == transcribing ]] || state=$HYPRVOICE_HOLD
    if [[ -s "${HYPRVOICE_SEQUENCE:-}" ]]; then
      state=$(head -n1 "$HYPRVOICE_SEQUENCE")
      tail -n +2 "$HYPRVOICE_SEQUENCE" >"$HYPRVOICE_SEQUENCE.tmp"
      mv "$HYPRVOICE_SEQUENCE.tmp" "$HYPRVOICE_SEQUENCE"
      printf '%s\n' "$state" >>"$VOICE_DICTATION_CALLS"
    fi
    [[ $state != status-error ]] || exit 1
    printf 'STATUS status=%s\n' "$state" ;;
  toggle)
    printf 'toggle\n' >>"$VOICE_DICTATION_CALLS"
    [[ ${HYPRVOICE_TOGGLE_FAIL:-0} == 0 ]] || exit 1
    [[ $state == idle ]] && printf transcribing >"$HYPRVOICE_STATE" || printf idle >"$HYPRVOICE_STATE"
    if [[ $state != idle && -n ${HYPRVOICE_STAGES:-} ]]; then
      printf '%s\n' "$HYPRVOICE_STAGES" >"$HYPRVOICE_SEQUENCE"
    fi
    [[ -z ${HYPRVOICE_READY:-} ]] || touch "$HYPRVOICE_READY"
    ;;
esac
SH
cat >"$test_root/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
case "$*" in
  '-j activewindow') printf '{"address":"%s"}\n' "${HYPR_ACTIVE:-}" ;;
  '-j clients')
    if [[ -n ${HYPR_CLIENTS:-} ]]; then printf '%s\n' "$HYPR_CLIENTS";
    else printf '[{"address":"0xaaa"},{"address":"0xbbb"}]\n'; fi ;;
  'getoption input:follow_mouse -j') printf '{"int":%s}\n' "${HYPR_FOLLOW:-1}" ;;
  'getoption cursor:no_warps -j')
    if [[ -n ${HYPR_WARPS_JSON:-} ]]; then printf '%s\n' "$HYPR_WARPS_JSON";
    else printf '{"bool":false}\n'; fi ;;
  -q\ *)
    shift
    printf '%s\n' "$*" >>"$VOICE_DICTATION_CALLS"
    [[ -z ${HYPR_FAIL_MATCH:-} || $* != *"$HYPR_FAIL_MATCH"* ]] || exit 1
    ;;
  *) exit 1 ;;
esac
SH
cat >"$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$VOICE_DICTATION_NOTIFICATIONS"
SH
# Players come from MEDIA_STATUS lines ("Playing spotify"); none by default.
cat >"$test_root/bin/playerctl" <<'SH'
#!/usr/bin/env bash
if [[ $* == '-a -i playerctld -f {{status}} {{playerInstance}} status' ]]; then
  [[ -n ${MEDIA_STATUS:-} ]] || { printf 'No players found\n' >&2; exit 1; }
  printf '%s\n' "$MEDIA_STATUS"
elif [[ $# == 3 && $1 == -p && $3 =~ ^(pause|play)$ ]]; then
  printf '%s %s\n' "$2" "$3" >>"$VOICE_DICTATION_CALLS"
else
  exit 2
fi
SH
chmod +x "$test_root/bin/wpctl" "$test_root/bin/pw-dump" "$test_root/bin/hyprvoice" \
  "$test_root/bin/notify-send" "$test_root/bin/hyprctl" "$test_root/bin/playerctl"

config="$test_root/voice-dictation.json"
hyprvoice_config="$test_root/hyprvoice/config.toml"
calls="$test_root/calls"
notifications="$test_root/notifications"
cat >"$hyprvoice_config" <<'TOML'
[recording]
  device = "old-primary"
  sample_rate = 16000
  device = "old-duplicate"
TOML
export PATH="$test_root/bin:$PATH" VOICE_DICTATION_CONFIG="$config"
export HYPRVOICE_CONFIG="$hyprvoice_config" VOICE_DICTATION_CALLS="$calls"
export VOICE_DICTATION_NOTIFICATIONS="$notifications"
export HYPRVOICE_STATE="$test_root/hyprvoice-state" VOICE_DICTATION_TARGET="$test_root/target"
export HYPRVOICE_SEQUENCE="$test_root/sequence"

"$script" use-default-output
[[ $("$script" resolve-source) == bluez_input.airpods ]] || fail 'default output does not resolve to its matching source'
"$script" toggle
[[ $(<"$calls") == toggle ]] || fail 'toggle did not invoke hyprvoice'
grep -Fq 'device = "bluez_input.airpods"' "$hyprvoice_config" || fail 'resolved source was not written to Hyprvoice recording config'
[[ $(grep -c '^[[:space:]]*device[[:space:]]*=' "$hyprvoice_config") == 1 ]] || fail 'Hyprvoice config has duplicate device keys'
[[ ! -e $notifications ]] || fail 'paired microphone selection produced a fallback notification'
python3 - "$hyprvoice_config" <<'PY' || fail 'Hyprvoice config is not valid TOML'
import sys
import tomllib

with open(sys.argv[1], 'rb') as config:
    assert tomllib.load(config)['recording']['device'] == 'bluez_input.airpods'
PY

config_inode=$(stat -c %i "$hyprvoice_config")
"$script" toggle
[[ $(stat -c %i "$hyprvoice_config") == "$config_inode" ]] || fail 'unchanged microphone rewrote the watched Hyprvoice config'

VOICE_DICTATION_SINK_DEVICE_ID=999 "$script" toggle
grep -Fq 'device = "alsa_input.webcam"' "$hyprvoice_config" || fail 'missing paired microphone did not fall back to the default source'
grep -Fq 'Using Webcam microphone' "$notifications" || fail 'fallback microphone was not named in a notification'

"$script" use-source alsa_input.webcam
[[ $("$script" resolve-source) == alsa_input.webcam ]] || fail 'explicit source selection was not retained'
"$script" toggle --dry-run >"$test_root/dry-run"
grep -Fq 'action=would-toggle device=alsa_input.webcam' "$test_root/dry-run" || fail 'dry-run does not report the selected source'

# Start in window 0xaaa, stop from 0xbbb: the text must land in 0xaaa, with
# mouse focus held off while it types, then focus and settings come back.
: >"$calls"; printf idle >"$HYPRVOICE_STATE"
HYPR_ACTIVE=0xaaa "$script" toggle
[[ $(<"$test_root/target") == 0xaaa ]] || fail 'start did not remember the focused window'
HYPR_ACTIVE=0xbbb "$script" toggle
expected='toggle
eval hl.config({ input = { follow_mouse = 0 }, cursor = { no_warps = true } })
dispatch hl.dsp.focus({ window = "address:0xaaa" })
toggle
dispatch hl.dsp.focus({ window = "address:0xbbb" })
eval hl.config({ input = { follow_mouse = 1 }, cursor = { no_warps = false } })'
[[ $(<"$calls") == "$expected" ]] || { cat "$calls" >&2; fail 'stop did not type into the remembered window'; }
[[ ! -e $test_root/target ]] || fail 'remembered window outlived the dictation'

# A remembered window that has since closed leaves focus alone.
: >"$calls"
HYPR_ACTIVE=0xdead "$script" toggle
HYPR_ACTIVE=0xbbb "$script" toggle
[[ $(<"$calls") == $'toggle\ntoggle' ]] || fail 'closed window still changed focus'

restored=$'dispatch hl.dsp.focus({ window = "address:0xbbb" })\neval hl.config({ input = { follow_mouse = 1 }, cursor = { no_warps = false } })'

# Do not hand focus back until asynchronous processing and typing finish.
: >"$calls"; printf idle >"$HYPRVOICE_STATE"
HYPR_ACTIVE=0xaaa "$script" toggle
HYPR_ACTIVE=0xbbb HYPRVOICE_STAGES=$'transcribing\ninjecting\nprocessing\ninjecting\nidle' "$script" toggle
delayed=${expected/$'toggle\ndispatch hl.dsp.focus({ window = "address:0xbbb" })'/$'toggle\ntranscribing\ninjecting\nprocessing\ninjecting\nidle\ndispatch hl.dsp.focus({ window = "address:0xbbb" })'}
[[ $(<"$calls") == "$delayed" ]] || fail 'focus returned before processing and injection finished'

# Every failure after changing settings restores focus and configuration.
for failure in toggle focus config; do
  printf idle >"$HYPRVOICE_STATE"
  HYPR_ACTIVE=0xaaa "$script" toggle
  : >"$calls"
  failure_env=()
  case $failure in
    toggle) failure_env=(HYPRVOICE_TOGGLE_FAIL=1) ;;
    focus) failure_env=('HYPR_FAIL_MATCH=window = "address:0xaaa"') ;;
    config) failure_env=('HYPR_FAIL_MATCH=follow_mouse = 0') ;;
  esac
  if env "${failure_env[@]}" HYPR_ACTIVE=0xbbb "$script" toggle; then
    fail "$failure failure reported success"
  fi
  [[ $(tail -n2 "$calls") == "$restored" ]] || fail "$failure failure left focus or configuration changed"
done

# Preserve nondefault values, including Boolean true and older integer JSON.
for warps_json in '{"bool":true}' '{"int":1}'; do
  printf idle >"$HYPRVOICE_STATE"
  HYPR_ACTIVE=0xaaa "$script" toggle
  : >"$calls"
  HYPR_ACTIVE=0xbbb HYPR_FOLLOW=2 HYPR_WARPS_JSON="$warps_json" "$script" toggle
  if [[ $warps_json == *bool* ]]; then warps=true; else warps=1; fi
  [[ $(tail -n1 "$calls") == "eval hl.config({ input = { follow_mouse = 2 }, cursor = { no_warps = $warps } })" ]] ||
    fail 'nondefault configuration was not restored'
done

# An unreadable option falls back; a lost status restores the transaction.
printf idle >"$HYPRVOICE_STATE"
HYPR_ACTIVE=0xaaa "$script" toggle
: >"$calls"
HYPR_ACTIVE=0xbbb HYPR_WARPS_JSON='{}' "$script" toggle
[[ $(<"$calls") == toggle ]] || fail 'unreadable option still mutated focus'
printf idle >"$HYPRVOICE_STATE"
HYPR_ACTIVE=0xaaa "$script" toggle
: >"$calls"
HYPR_ACTIVE=0xbbb HYPRVOICE_STAGES=status-error "$script" toggle
[[ $(tail -n2 "$calls") == "$restored" ]] || fail 'lost status left settings changed'

# A repeat press during a transaction is ignored.
: >"$calls"
exec 8>"$VOICE_DICTATION_TARGET.lock"
flock -x 8
"$script" toggle
[[ ! -s $calls ]] || fail 'overlapping invocation toggled dictation'
flock -u 8
exec 8>&-

# A busy daemon can outlive the wrapper (closed target, timeout, interruption).
# Repeated presses must not send another injection action in either stage.
for state in processing injecting; do
  printf '%s' "$state" >"$HYPRVOICE_STATE"
  : >"$calls"
  "$script" toggle
  [[ ! -s $calls ]] || fail "repeat press toggled Hyprvoice during $state"
done

# TERM during delayed typing runs the same restoration trap.
printf idle >"$HYPRVOICE_STATE"
HYPR_ACTIVE=0xaaa "$script" toggle
: >"$calls"
HYPR_ACTIVE=0xbbb HYPRVOICE_HOLD=processing HYPRVOICE_READY="$test_root/ready" "$script" toggle &
dictation_pid=$!
for _ in {1..100}; do
  [[ ! -e $test_root/ready ]] || break
  sleep 0.01
done
kill -TERM "$dictation_pid"
if wait "$dictation_pid"; then fail 'interrupted dictation reported success'; fi
[[ $(tail -n2 "$calls") == "$restored" ]] || fail 'TERM left settings changed'

# Playing media pauses before listening starts and only those players resume
# once listening stops, without waiting for the text to be typed.
playing=$'Playing spotify\nPaused firefox.instance_1_2\nPlaying chromium.instance42'
printf idle >"$HYPRVOICE_STATE"
: >"$calls"
HYPR_ACTIVE=0xaaa MEDIA_STATUS="$playing" "$script" toggle
[[ $(<"$calls") == $'spotify pause\nchromium.instance42 pause\ntoggle' ]] ||
  { cat "$calls" >&2; fail 'start did not pause playing media first'; }
: >"$calls"
HYPR_ACTIVE=0xbbb HYPRVOICE_STAGES=$'injecting\nidle' "$script" toggle
expected='eval hl.config({ input = { follow_mouse = 0 }, cursor = { no_warps = true } })
dispatch hl.dsp.focus({ window = "address:0xaaa" })
toggle
spotify play
chromium.instance42 play
injecting
idle
dispatch hl.dsp.focus({ window = "address:0xbbb" })
eval hl.config({ input = { follow_mouse = 1 }, cursor = { no_warps = false } })'
[[ $(<"$calls") == "$expected" ]] || { cat "$calls" >&2; fail 'stop did not resume only the paused media'; }
[[ ! -e $VOICE_DICTATION_TARGET.media ]] || fail 'paused media list outlived the dictation'

# Media resumes on the fallback stop path and when Hyprvoice fails either way.
for case in fallback stop-fail start-fail; do
  printf idle >"$HYPRVOICE_STATE"
  start_env=() stop_env=(HYPR_ACTIVE=0xbbb)
  case $case in
    fallback) start_env=(HYPR_ACTIVE=0xdead) ;;
    stop-fail) stop_env+=(HYPRVOICE_TOGGLE_FAIL=1) ;;
    start-fail) start_env=(HYPRVOICE_TOGGLE_FAIL=1) ;;
  esac
  : >"$calls"
  if env HYPR_ACTIVE=0xaaa MEDIA_STATUS='Playing spotify' "${start_env[@]}" "$script" toggle; then
    [[ $case != start-fail ]] || fail 'failed start reported success'
    if env "${stop_env[@]}" "$script" toggle; then
      [[ $case != stop-fail ]] || fail 'failed stop reported success'
    fi
  fi
  grep -Fxq 'spotify play' "$calls" || fail "$case did not resume media"
  [[ $case != fallback ]] || ! grep -Fq dispatch "$calls" || fail 'fallback stop changed focus'
  [[ ! -e $VOICE_DICTATION_TARGET.media ]] || fail "$case left the paused media list behind"
done

# A list left by an interrupted dictation never resumes stale players.
printf 'stale-player\n' >"$VOICE_DICTATION_TARGET.media"
printf idle >"$HYPRVOICE_STATE"
: >"$calls"
HYPR_ACTIVE=0xaaa "$script" toggle
HYPR_ACTIVE=0xbbb "$script" toggle
! grep -Fq stale-player "$calls" || fail 'stale paused media was resumed'

# "pause_media": false leaves media alone and survives choosing a microphone.
jq '. + {pause_media: false}' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
"$script" use-default-output
[[ $(jq -r .pause_media "$config") == false ]] || fail 'choosing a microphone dropped pause_media'
printf idle >"$HYPRVOICE_STATE"
: >"$calls"
HYPR_ACTIVE=0xaaa MEDIA_STATUS="$playing" "$script" toggle
HYPR_ACTIVE=0xbbb "$script" toggle
! grep -Eq ' (pause|play)$' "$calls" || fail 'pause_media=false still controlled media'
"$script" use-source alsa_input.webcam

# Atomic writes replace a target symlink without touching its destination.
printf 'keep me\n' >"$test_root/victim"
ln -s "$test_root/victim" "$VOICE_DICTATION_TARGET"
printf idle >"$HYPRVOICE_STATE"
HYPR_ACTIVE=0xaaa "$script" toggle
[[ $(<"$test_root/victim") == 'keep me' && ! -L $VOICE_DICTATION_TARGET ]] || fail 'target write followed a symlink'

# Without a session runtime directory, use private per-user cache storage.
printf idle >"$HYPRVOICE_STATE"
env -u VOICE_DICTATION_TARGET -u XDG_RUNTIME_DIR XDG_CACHE_HOME="$test_root/cache" \
  HYPR_ACTIVE=0xaaa "$script" toggle
[[ $(<"$test_root/cache/voice-dictation-target") == 0xaaa ]] || fail 'runtime fallback does not use user cache'
[[ $(stat -c %a "$test_root/cache/voice-dictation-target") == 600 ]] || fail 'target file is not private'

if "$script" use-source 'bad;source' >/dev/null 2>&1; then
  fail 'unsafe source name was accepted'
fi

grep -Fq 'cfg.scripts_dir .. "/voice-dictation toggle"' "$lua" || fail 'Lua binding bypasses microphone resolution'
grep -Fq "exec, \$scriptsDir/voice-dictation toggle" "$legacy" || fail 'legacy binding bypasses microphone resolution'
grep -Fq 'setup.voice-dictation' "$menu" || fail 'Setup menu lacks voice dictation settings'

printf 'voice dictation: ok\n'
