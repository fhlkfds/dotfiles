#!/usr/bin/env bash
# Clipboard dictation: the wl-copy and notify-send wrappers, then the real
# hyprvoice daemon driven through voice-dictation.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
wrapper_dir=$repo_root/systemd/.local/libexec/hyprvoice-gpu
script=$repo_root/hypr/.config/hypr/scripts/voice-dictation
test_root=$(mktemp -d)
daemon_groups=()
cleanup() {
  local group
  for group in "${daemon_groups[@]}"; do kill -TERM -- "-$group" 2>/dev/null || true; done
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for wrapper in wl-copy notify-send; do
  [[ -x $wrapper_dir/$wrapper ]] || fail "$wrapper wrapper is not executable"
  bash -n "$wrapper_dir/$wrapper"
done

# Stand-ins for the real tools. Every call lands in one ordered file.
real=$test_root/real
mkdir -p "$real"
cat >"$real/log-call" <<'SH'
line=$1
shift
for arg in "$@"; do line+=" [${arg//$'\n'/\\n}]"; done
printf '%s\n' "$line" >>"$CALLS"
SH
cat >"$real/wl-copy" <<'SH'
#!/usr/bin/env bash
. "$(dirname -- "$0")/log-call" wl-copy "$@"
[[ ${WLCOPY_STATUS:-0} == 0 ]] || exit "$WLCOPY_STATUS"
[[ $# != 0 ]] || cat >"$CLIP_FILE"
SH
cat >"$real/wl-paste" <<'SH'
#!/usr/bin/env bash
. "$(dirname -- "$0")/log-call" wl-paste "$@"
case ${WLPASTE_MODE:-ok} in
  ok) cat -- "$CLIP_FILE" ;;
  mismatch) printf 'something else' ;;
  fail) exit 1 ;;
  hang) exec sleep 10 ;;
esac
SH
cat >"$real/notify-send" <<'SH'
#!/usr/bin/env bash
. "$(dirname -- "$0")/log-call" notify-send "$@"
exit "${NOTIFY_STATUS:-0}"
SH
chmod +x "$real/wl-copy" "$real/wl-paste" "$real/notify-send"

export CALLS=$test_root/calls CLIP_FILE=$test_root/clipboard
export HYPRVOICE_WL_COPY=$real/wl-copy HYPRVOICE_WL_PASTE=$real/wl-paste HYPRVOICE_NOTIFY_SEND=$real/notify-send
export HYPRVOICE_CLIPBOARD_CONFIRM_TIMEOUT=0.3

reset() { : >"$CALLS"; rm -f -- "$CLIP_FILE"; }
calls() { cat -- "$CALLS"; }
ready='notify-send [-a] [Hyprvoice] [-r] [9932] [Hyprvoice] [Dictation copied — ready to paste]'

reset
text='café — ok  '
printf '%s' "$text" | "$wrapper_dir/wl-copy"
[[ $(calls) == $'wl-copy\nwl-paste [--no-newline]\n'"$ready" ]] || { calls >&2; fail 'a copy was not read back before the ready notice'; }
[[ $(<"$CLIP_FILE") == "$text" ]] || fail 'the clipboard does not hold the dictated text'

reset
NOTIFY_STATUS=1 "$wrapper_dir/wl-copy" <<<'text' || fail 'a failed notice turned a good copy into an error'

reset
status=0
printf 'text' | WLCOPY_STATUS=7 "$wrapper_dir/wl-copy" || status=$?
[[ $status == 7 ]] || fail "a wl-copy failure exited $status instead of 7"
[[ $(calls) == wl-copy ]] || fail 'a failed copy was read back or announced'

for mode in mismatch fail hang; do
  reset
  status=0
  printf 'text' | WLPASTE_MODE=$mode "$wrapper_dir/wl-copy" 2>"$test_root/err" || status=$?
  [[ $status == 1 ]] || fail "readback $mode exited $status instead of 1"
  [[ $(calls) == $'wl-copy\nwl-paste [--no-newline]' ]] || fail "readback $mode was announced"
  [[ -s $test_root/err ]] || fail "readback $mode was silent"
done

reset
printf '' | "$wrapper_dir/wl-copy"
[[ $(calls) == wl-copy ]] || fail 'empty input was read back or announced'

reset
"$wrapper_dir/wl-copy" --clear </dev/null
[[ $(calls) == 'wl-copy [--clear]' ]] || fail 'arguments were not passed straight through'

reset
"$wrapper_dir/notify-send" -a Hyprvoice Hyprvoice 'Recording Started'
"$wrapper_dir/notify-send" -a Hyprvoice -u critical 'Hyprvoice Error' 'Failed to inject text: wl-copy failed: exit status 1'
"$wrapper_dir/notify-send" -a Hyprvoice -u critical 'Hyprvoice Error' 'Failed to inject text: cannot inject empty text'
HYPRVOICE_NOTIFY_ID=4242 "$wrapper_dir/notify-send" -a Hyprvoice Hyprvoice 'Config Reloaded'
"$wrapper_dir/notify-send" -a 'Voice dictation' -r 9931 -t 2500 'Voice dictation' 'Using Webcam microphone'
"$wrapper_dir/notify-send" -u critical 'Other' 'App'
expected='notify-send [-a] [Hyprvoice] [-r] [9932] [Hyprvoice] [Recording Started]
notify-send [-a] [Hyprvoice] [-r] [9932] [-u] [critical] [Dictation failed] [Failed to inject text: wl-copy failed: exit status 1\nNothing new was typed or copied.]
notify-send [-a] [Hyprvoice] [-r] [9932] [-u] [critical] [Dictation failed] [No speech was recognized.\nNothing new was typed or copied.]
notify-send [-a] [Hyprvoice] [-r] [4242] [Hyprvoice] [Config Reloaded]
notify-send [-a] [Voice dictation] [-r] [9931] [-t] [2500] [Voice dictation] [Using Webcam microphone]
notify-send [-u] [critical] [Other] [App]'
[[ $(calls) == "$expected" ]] || { calls >&2; fail 'notify-send arguments were not rewritten as designed'; }

hyprvoice=$(command -v hyprvoice || true)
if [[ -z $hyprvoice ]]; then
  printf 'skip: hyprvoice not installed\n'
  printf 'hyprvoice clipboard wrappers: ok\n'
  exit 0
fi
command -v setsid >/dev/null || {
  printf 'skip: setsid not installed\n'
  printf 'hyprvoice clipboard wrappers: ok\n'
  exit 0
}
base_path=$PATH

wait_for() {
  local tries=$1 i
  shift
  for ((i = 0; i < tries * 10; i++)); do
    "$@" && return 0
    sleep 0.1
  done
  return 1
}

# e2e NAME [VAR=value...]: run one dictation (start, then stop) through
# voice-dictation against a private daemon, then print the ordered call log.
e2e_dictation() {
  local name=$1 outcome=$2
  shift 2
  local d=$test_root/e2e-$name stubs
  stubs=$d/stubs
  mkdir -p "$stubs" "$d/run" "$d/home/.local/share/hyprvoice/models/whisper" "$d/config/hyprvoice" "$d/cache" "$d/data"
  chmod 700 "$d/run"
  : >"$d/home/.local/share/hyprvoice/models/whisper/ggml-base.en.bin"
  mkdir -p "$d/gpu-prefix"

  cat >"$stubs/pw-cli" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat >"$stubs/pw-record" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$E2E_DIR/pw-record.pid"
head -c 6400 /dev/zero
exec sleep 3600
SH
  cat >"$stubs/whisper-cli" <<'SH'
#!/usr/bin/env bash
printf '%s' "${E2E_TRANSCRIPT-}"
SH
  cat >"$stubs/wpctl" <<'SH'
#!/usr/bin/env bash
[[ $2 == @DEFAULT_AUDIO_SINK@ ]] && printf '  * device.id = "7"\n'
exit 0
SH
  cat >"$stubs/pw-dump" <<'SH'
#!/usr/bin/env bash
printf '[{"type":"PipeWire:Interface:Node","info":{"props":{"media.class":"Audio/Source","node.name":"e2e_mic","node.description":"E2E mic","device.id":"7"}}}]\n'
SH
  cat >"$stubs/hyprctl" <<'SH'
#!/usr/bin/env bash
[[ $* == '-j activewindow' ]] && printf '{}\n'
exit 0
SH
  chmod +x "$stubs"/*

  cat >"$d/config/hyprvoice/config.toml" <<'TOML'
[recording]
sample_rate = 16000
channels = 1
format = "s16"
buffer_size = 8192
device = "e2e_mic"
channel_buffer_size = 30
timeout = "5m"

[transcription]
provider = "whisper-cpp"
language = "en"
model = "base.en"
streaming = false
threads = 1

[injection]
backends = ["ydotool", "wtype", "clipboard"]
ydotool_timeout = "5s"
wtype_timeout = "5s"
clipboard_timeout = "3s"

[notifications]
enabled = true
type = "desktop"
TOML

  (
    export HOME=$d/home XDG_CONFIG_HOME=$d/config XDG_CACHE_HOME=$d/cache XDG_DATA_HOME=$d/data \
      XDG_RUNTIME_DIR=$d/run WAYLAND_DISPLAY=wayland-e2e E2E_DIR=$d CALLS=$d/calls CLIP_FILE=$d/clipboard \
      HYPRVOICE_PW_RECORD=$stubs/pw-record HYPRVOICE_CPU_WHISPER_CLI=$stubs/whisper-cli \
      HYPRVOICE_GPU_PREFIX=$d/gpu-prefix HYPRVOICE_CLIPBOARD_CONFIRM_TIMEOUT=2
    for assignment in "$@"; do export "${assignment?}"; done
    : >"$CALLS"

    dictation() {
      env PATH="$stubs:$base_path" HYPRVOICE="$hyprvoice" HYPRCTL="$stubs/hyprctl" PLAYERCTL="$d/no-playerctl" \
        VOICE_DICTATION_CONFIG="$d/voice-dictation.json" HYPRVOICE_CONFIG="$d/config/hyprvoice/config.toml" \
        VOICE_DICTATION_TARGET="$d/run/target" "$script" "$@"
    }
    status_is() { [[ $("$hyprvoice" status 2>/dev/null) == "STATUS status=$1" ]]; }
    calls_match() { grep -Eq -- "$1" "$CALLS"; }

    dictation use-clipboard
    grep -Fq 'backends = ["clipboard"]' "$d/config/hyprvoice/config.toml" || fail "$name: clipboard mode was not configured"

    PATH="$wrapper_dir:$stubs:/usr/bin:/bin" setsid "$hyprvoice" serve >"$d/daemon.log" 2>&1 &
    daemon=$!
    printf '%s' "$daemon" >"$d/daemon.pid"
    trap 'kill -TERM -- "-$daemon" 2>/dev/null || true; kill "$(cat "$d/pw-record.pid" 2>/dev/null)" 2>/dev/null || true' EXIT
    wait_for 100 status_is idle || { cat "$d/daemon.log" >&2; fail "$name: the daemon did not start"; }

    dictation toggle >/dev/null
    wait_for 100 status_is transcribing || { cat "$d/daemon.log" >&2; fail "$name: dictation did not start"; }
    wait_for 50 calls_match 'Recording Started' || fail "$name: no Recording Started notice"

    if [[ $outcome == cancel ]]; then
      "$hyprvoice" cancel >/dev/null
      wait_for 50 calls_match 'Operation Cancelled' || fail "$name: no cancel notice"
    else
      dictation toggle >/dev/null
      case $outcome in
        ready) wait_for 100 calls_match 'ready to paste' || { cat "$d/daemon.log" >&2; fail "$name: no ready notice"; } ;;
        *) wait_for 100 calls_match 'Dictation failed' || { cat "$d/daemon.log" >&2; fail "$name: no failure notice"; } ;;
      esac
    fi
    wait_for 100 status_is idle || fail "$name: the daemon did not return to idle"
    cp -- "$CALLS" "$d/calls.final"
    [[ ! -e $CLIP_FILE ]] || cp -- "$CLIP_FILE" "$d/clipboard.final"
  )
  e2e_dir=$d
  daemon_groups+=("$(cat "$d/daemon.pid" 2>/dev/null || true)")
}

slot='[-a] [Hyprvoice] [-r] [9932]'
recording="notify-send $slot [Hyprvoice] [Recording Started]"
transcribing="notify-send $slot [Hyprvoice] [Transcribing…]"

e2e_dictation success ready 'E2E_TRANSCRIPT=hello from the clipboard test'
expected=$recording$'\n'$transcribing$'\nwl-copy\nwl-paste [--no-newline]\n'"$ready"
[[ $(<"$e2e_dir/calls.final") == "$expected" ]] || { cat "$e2e_dir/calls.final" >&2; fail 'success: the notices are not Recording, Transcribing, ready in order'; }
[[ $(<"$e2e_dir/clipboard.final") == 'hello from the clipboard test' ]] || fail 'success: the clipboard does not hold the transcript'

e2e_dictation copy-fails failure 'E2E_TRANSCRIPT=hello' WLCOPY_STATUS=1
! grep -Fq 'ready to paste' "$e2e_dir/calls.final" || fail 'copy-fails: a ready notice followed a failed copy'
! grep -Fq 'wl-paste' "$e2e_dir/calls.final" || fail 'copy-fails: a failed copy was read back'
grep -Fq "notify-send $slot [-u] [critical] [Dictation failed] [" "$e2e_dir/calls.final" || fail 'copy-fails: no failure notice in the slot'

e2e_dictation readback-fails failure 'E2E_TRANSCRIPT=hello' WLPASTE_MODE=mismatch
! grep -Fq 'ready to paste' "$e2e_dir/calls.final" || fail 'readback-fails: a ready notice followed a clipboard mismatch'
grep -Fq '[Dictation failed]' "$e2e_dir/calls.final" || fail 'readback-fails: no failure notice'

e2e_dictation empty failure 'E2E_TRANSCRIPT='
! grep -Fq 'ready to paste' "$e2e_dir/calls.final" || fail 'empty: a ready notice followed silence'
! grep -Eq '^wl-(copy|paste)' "$e2e_dir/calls.final" || fail 'empty: the clipboard was touched'
grep -Fq "[Dictation failed] [No speech was recognized.\\nNothing new was typed or copied.]" "$e2e_dir/calls.final" ||
  fail 'empty: silence was not reported as no speech'

e2e_dictation cancel cancel 'E2E_TRANSCRIPT=hello'
! grep -Fq 'ready to paste' "$e2e_dir/calls.final" || fail 'cancel: a ready notice followed a cancel'
! grep -Eq '^wl-(copy|paste)' "$e2e_dir/calls.final" || fail 'cancel: the clipboard was touched'

for name in success copy-fails readback-fails empty cancel; do
  ! grep -E '^notify-send' "$test_root/e2e-$name/calls.final" | grep -Fvq -- "$slot" ||
    fail "$name: a Hyprvoice notice bypassed the shared slot"
done

printf 'hyprvoice clipboard wrappers: ok\n'
