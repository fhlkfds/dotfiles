#!/usr/bin/env bash
# Drives voice-captions serve end to end with the fake engine and a stub
# recorder in a private runtime dir. Opt-in real-engine case: set
# VOICE_CAPTIONS_REAL_MODEL_DIR and VOICE_CAPTIONS_PYTHON (a Python with sherpa_onnx).
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
vc=$repo_root/systemd/.local/bin/voice-captions
unit=$repo_root/systemd/.config/systemd/user/voice-captions.service
real_model=${VOICE_CAPTIONS_REAL_MODEL_DIR:-}
real_python=${VOICE_CAPTIONS_PYTHON:-}
unset VOICE_CAPTIONS_CONTROL VOICE_CAPTIONS_EVENTS VOICE_CAPTIONS_PYTHON VOICE_CAPTIONS_PIP \
  VOICE_CAPTIONS_CURL VOICE_CAPTIONS_MODEL_DIR VOICE_CAPTIONS_REAL_MODEL_DIR
test_root=$(mktemp -d -t voice-captions-test.XXXXXX)
daemon_pid=
background=()
cleanup() {
  local pid
  for pid in "${background[@]}" $daemon_pid; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [[ ! -s $test_root/daemon.log ]] || sed 's/^/  daemon: /' "$test_root/daemon.log" >&2
  exit 1
}

[[ -x $vc ]] || fail 'voice-captions is not executable'
python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$vc" || fail 'voice-captions does not parse'

export HOME=$test_root/home XDG_RUNTIME_DIR=$test_root/run
# A decoy: the venv and model live in ~/.local/share whatever XDG_DATA_HOME says,
# because the service unit and the menu guards name that path.
export XDG_DATA_HOME=$HOME/decoy-data PYTHONDONTWRITEBYTECODE=1
export VOICE_CAPTIONS_ENGINE=fake VOICE_CAPTIONS_RECORDER=$test_root/bin/recorder
export RECORDER_LOG=$test_root/recorder.log
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$test_root/bin"
chmod 700 "$XDG_RUNTIME_DIR"
fifo=$XDG_RUNTIME_DIR/voice-captions/control
events=$XDG_RUNTIME_DIR/voice-captions/events.sock

# Half a fake word per write, so the tentative tail is exercised too, at a
# steady -18 dBFS. It outlives a closed pipe, so only the daemon's signals can stop it.
cat >"$test_root/bin/recorder" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$$" "$*" >>"$RECORDER_LOG"
exec python3 -c '
import sys, time
while True:
    try:
        sys.stdout.buffer.write(b"\x00\x10" * 800)
        sys.stdout.buffer.flush()
    except OSError:
        pass
    time.sleep(0.05)
'
SH
chmod +x "$test_root/bin/recorder"

# Ready once it logs; a killed daemon's socket and FIFO may still be there.
start_daemon() {
  local python=${1:-python3} starts
  starts=$(grep -c '^voice-captions: listening on' "$test_root/daemon.log" 2>/dev/null || true)
  "$python" "$vc" serve 2>>"$test_root/daemon.log" &
  daemon_pid=$!
  for _ in {1..1200}; do
    (( $(grep -c '^voice-captions: listening on' "$test_root/daemon.log") > starts )) && return 0
    kill -0 "$daemon_pid" 2>/dev/null || fail 'the daemon exited at start'
    sleep 0.025
  done
  fail 'the daemon did not start listening'
}
stop_daemon() {
  local pid
  for pid in "${background[@]}"; do kill "$pid" 2>/dev/null || true; done
  background=()
  kill -TERM "$daemon_pid"
  wait "$daemon_pid" || fail 'the daemon did not exit cleanly on TERM'
  daemon_pid=
}
report() { printf '%s\n' "$*" 1<>"$fifo"; }
watcher() {
  python3 "$vc" watch >"$1" &
  background+=($!)
  wait_for "$1" '"phase":'
}
wait_for() {
  for _ in {1..400}; do
    grep -Fq -- "$2" "$1" 2>/dev/null && return 0
    sleep 0.025
  done
  fail "never saw $2 in ${1##*/}"
}
gone() {
  for _ in {1..120}; do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.025
  done
  return 1
}
recorder_pid() {
  for _ in {1..200}; do
    (( $(wc -l <"$RECORDER_LOG" 2>/dev/null || echo 0) >= $1 )) && { sed -n "$1s/ .*//p" "$RECORDER_LOG"; return; }
    sleep 0.025
  done
  fail "recorder $1 never started"
}

start_daemon
[[ $(stat -c %a "${fifo%/*}") == 700 && $(stat -c %a "$fifo") == 600 && $(stat -c %a "$events") == 600 ]] ||
  fail 'the runtime dir, FIFO or socket is not private'

watcher "$test_root/session"
report 100.1 armed
wait_for "$test_root/session" '"phase":"armed"'
report 100.1 'listening alsa_input.test'
wait_for "$test_root/session" '"committed":"word1 word2 word3 '
first=$(recorder_pid 1)
[[ $(sed -n '1s/^[0-9]* //p' "$RECORDER_LOG") == '--target alsa_input.test --rate 16000 --channels 1 --format s16 -' ]] ||
  fail "recorder arguments: $(<"$RECORDER_LOG")"
report 100.1 typing
wait_for "$test_root/session" '"phase":"typing"'
gone "$first" || fail 'the recorder still runs after typing'
report 100.1 idle
wait_for "$test_root/session" '"id":"100.1","phase":"idle"'
python3 - "$test_root/session" <<'PY' || fail 'the session events are wrong'
import json, sys
everything = [json.loads(line) for line in open(sys.argv[1])]
typing_at = next(i for i, e in enumerate(everything) if e.get("phase") == "typing")
levels = [e for e in everything[:typing_at] if e["type"] == "level"]
assert levels and all(e == {"type": "level", "v": 1, "id": "100.1", "level": 0.7} for e in levels), levels
assert not [e for e in everything[typing_at:] if e["type"] == "level"], "a level was sent after typing"
events = [e for e in everything if e["type"] == "state"]
seqs = [e["seq"] for e in events]
assert all(a < b for a, b in zip(seqs, seqs[1:])), seqs
phases = [e["phase"] for e in events]
deduped = [p for i, p in enumerate(phases) if i == 0 or phases[i - 1] != p]
assert deduped == ["idle", "armed", "listening", "typing", "idle"], deduped
spoken = [e for e in events if e["phase"] in ("listening", "typing")]
committed = [e["committed"] for e in spoken]
assert all(b.startswith(a) for a, b in zip(committed, committed[1:])), committed
assert len(set(committed)) >= 3, committed
assert any(e["tentative"] for e in spoken), "no tentative text was ever shown"
last = [e for e in events if e["phase"] == "typing"][-1]
assert last["committed"].startswith("word1 word2 word3 "), last
assert events[-1] == {"type": "state", "v": 1, "seq": seqs[-1], "id": "100.1", "phase": "idle",
                      "committed": "", "tentative": "", "note": ""}, events[-1]
PY

report 200 armed
report '200 listening alsa_input.test'
second=$(recorder_pid 2)
kill -KILL "$second"
python3 "$vc" watch --until-note no-audio --timeout 5 >/dev/null || fail 'a killed recorder did not show no-audio'
kill -0 "$daemon_pid" || fail 'the daemon died with its recorder'

started=$EPOCHREALTIME
python3 "$vc" watch --until-phase listening --timeout 2 >"$test_root/late" || fail 'a late reader got no snapshot'
awk -v a="${started/,/.}" -v b="${EPOCHREALTIME/,/.}" 'BEGIN { exit !(b - a < 1) }' || fail 'the snapshot was not sent at once'
[[ $(wc -l <"$test_root/late") == 1 ]] && grep -Fq '"id":"200","phase":"listening"' "$test_root/late" ||
  fail "late snapshot: $(<"$test_root/late")"

report '250 listening alsa_input.test'
third=$(recorder_pid 3)
report 300 armed
python3 "$vc" watch --until-phase armed --timeout 2 | grep -Fq '"id":"300"' || fail 'a newer id did not pre-empt'
gone "$third" || fail 'the pre-empted recorder still runs'
report 250 typing
report '300 listening'
report 'junk line'
printf 'x%.0s' {1..5000} 1<>"$fifo"
python3 "$vc" watch --until-phase armed --timeout 2 | grep -Fq '"id":"300","phase":"armed"' ||
  fail 'a stale, malformed or junk report changed the state'
report 300 idle

python3 -c '
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(60)
' "$events" &
background+=($!)
watcher "$test_root/busy"
report 400 armed
report '400 listening alsa_input.test'
wait_for "$test_root/busy" '"committed":"word1 word2 word3 word4 word5 '
report 400 typing
report 400 idle
wait_for "$test_root/busy" '"id":"400","phase":"idle"'

report '500 listening alsa_input.test'
fifth=$(recorder_pid 5)
stop_daemon
gone "$fifth" || fail 'the recorder outlived the daemon'
[[ ! -e $fifo && ! -e $events ]] || fail 'the daemon left its FIFO or socket behind'

start_daemon
timeout 5 python3 "$vc" serve 2>"$test_root/second.log" &&
  fail 'a second daemon started'
grep -Fq 'another daemon' "$test_root/second.log" || fail 'a second daemon did not say why it stopped'
python3 "$vc" watch --until-phase idle --timeout 2 >/dev/null || fail 'a second daemon broke the first'
kill -KILL "$daemon_pid"
wait "$daemon_pid" 2>/dev/null || true
daemon_pid=
[[ -S $events && -p $fifo ]] || fail 'expected a killed daemon to leave its socket'
VOICE_CAPTIONS_FAKE_LOAD=0.8 start_daemon
watcher "$test_root/loading"
report 600 armed
report '600 listening alsa_input.test'
wait_for "$test_root/loading" '"committed":"word1 word2 word3 word4 word5 word6 word7 word8 '
report 600 idle
python3 - "$test_root/loading" <<'PY' || fail 'a stale socket was not replaced, or audio recorded while loading was lost'
import json, sys
events = [e for e in map(json.loads, open(sys.argv[1])) if e["type"] == "state"]
assert any(e["phase"] == "listening" and e["note"] == "loading" for e in events), "loading was never noted"
first = next(e["committed"] for e in events if e["committed"])
assert len(first.split()) >= 6, f"the first words after loading were {first!r}"
PY
stop_daemon

VOICE_CAPTIONS_ARMED_TIMEOUT=0.3 start_daemon
report 700 armed
python3 "$vc" watch --until-phase idle --timeout 3 >"$test_root/deadline" || fail 'the armed deadline did not return to idle'
grep -Fq '"id":"700","phase":"idle"' "$test_root/deadline" || fail "deadline events: $(<"$test_root/deadline")"
stop_daemon

VOICE_CAPTIONS_FAKE_LOAD=fail start_daemon
report 800 armed
python3 "$vc" watch --until-note engine-failed --timeout 3 >/dev/null || fail 'a failed model load was not noted'
stop_daemon

calls=$test_root/install-calls
for tool in python curl pip systemctl; do
  cat >"$test_root/bin/$tool" <<SH
#!/usr/bin/env bash
printf '$tool %s\n' "\$*" >>"$calls"
exit 1
SH
  chmod +x "$test_root/bin/$tool"
done
install_env=(VOICE_CAPTIONS_PYTHON="$test_root/bin/python" VOICE_CAPTIONS_PIP="$test_root/bin/pip"
  VOICE_CAPTIONS_CURL="$test_root/bin/curl" PATH="$test_root/bin:$PATH")
tree() { find "$HOME" -printf '%p %s %T@\n' | sort; }
before=$(tree)
env "${install_env[@]}" python3 "$vc" install --dry-run >"$test_root/dry-run" || fail 'install --dry-run failed'
[[ ! -e $calls ]] || fail "install --dry-run ran: $(<"$calls")"
[[ $(tree) == "$before" ]] || fail 'install --dry-run changed files'
for expected in "-m venv $HOME/.local/share/voice-captions/venv" 'install --require-hashes' 'sherpa-onnx==2.0.3' \
  'sherpa-onnx-core==2.0.3' 'sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25.tar.bz2' \
  '78e2b79fcf7271553a74402a76b771b09ea40117a39566a79f52235b23db6358 before unpacking' 'test_wavs/0.wav' \
  'systemctl --user enable --now voice-captions.service'; do
  grep -Fq -- "$expected" "$test_root/dry-run" || fail "install --dry-run does not mention: $expected"
done
[[ $(grep -c -- '--hash=sha256:' "$test_root/dry-run") == 9 ]] || fail 'install --dry-run does not pin all nine wheel hashes'
python3 "$vc" install --bogus >/dev/null 2>&1 && fail 'install accepted a bad flag'
status=0; python3 "$vc" install --bogus >/dev/null 2>&1 || status=$?
[[ $status == 2 ]] || fail "a bad flag exited $status, not 2"

cat >"$test_root/bin/python" <<'SH'
#!/usr/bin/env bash
printf 'python %s\n' "$*" >>"$INSTALL_CALLS"
[[ $1 == -m && $2 == venv ]] || exit 1
mkdir -p "$3/bin"
printf '#!/usr/bin/env bash\nprintf "venv-python %%s\\n" "$*" >>"$INSTALL_CALLS"\n' >"$3/bin/python"
chmod +x "$3/bin/python"
SH
cat >"$test_root/bin/pip" <<'SH'
#!/usr/bin/env bash
printf 'pip %s\n' "$*" >>"$INSTALL_CALLS"
cp -- "${@: -1}" "$INSTALL_CALLS.requirements"
SH
cat >"$test_root/bin/curl" <<'SH'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$INSTALL_CALLS"
while (($#)); do [[ $1 == -o ]] && { cp -- "$FIXTURE_ARCHIVE" "$2"; exit 0; }; shift; done
exit 1
SH
model=sherpa-onnx-nemotron-speech-streaming-en-0.6b-560ms-int8-2026-04-25
mkdir -p "$test_root/fixture/$model/test_wavs"
touch "$test_root/fixture/$model"/{encoder.int8.onnx,decoder.int8.onnx,joiner.int8.onnx,tokens.txt,unpacked-marker}
touch "$test_root/fixture/$model/test_wavs"/{0.wav,trans.txt}
tar -cjf "$test_root/fixture.tar.bz2" -C "$test_root/fixture" "$model"
status=0
env "${install_env[@]}" INSTALL_CALLS="$calls" FIXTURE_ARCHIVE="$test_root/fixture.tar.bz2" \
  python3 "$vc" install >"$test_root/install.out" 2>&1 || status=$?
[[ $status == 1 ]] || fail "a wrong-checksum install exited $status: $(<"$test_root/install.out")"
grep -Fq 'refusing to unpack' "$test_root/install.out" || fail 'the checksum refusal was not explained'
[[ -z $(find "$HOME" -name unpacked-marker) ]] || fail 'a wrong-checksum archive was unpacked'
[[ ! -e $HOME/.local/share/voice-captions/models/$model ]] || fail 'a wrong-checksum model was moved into place'
[[ -z $(find "$HOME/.local/share/voice-captions/models" -mindepth 1) ]] || fail 'install left temporary files'
grep -q '^pip install --require-hashes .* -r ' "$calls" || fail "pip ran without --require-hashes: $(<"$calls")"
[[ $(grep -c -- '--hash=sha256:' "$calls.requirements") == 9 ]] || fail 'pip did not get all nine hashes'
! grep -q '^venv-python\|^systemctl' "$calls" || fail "install ran the self-test or systemctl after a refusal: $(<"$calls")"

if command -v systemd-analyze >/dev/null 2>&1; then
  unit_home=$test_root/unit-home
  mkdir -p "$unit_home/.local/share/voice-captions/venv/bin" "$unit_home/.local/bin"
  for executable in "$unit_home/.local/share/voice-captions/venv/bin/python" "$unit_home/.local/bin/voice-captions"; do
    printf '#!/bin/sh\n' >"$executable"
    chmod +x "$executable"
  done
  HOME=$unit_home systemd-analyze --user verify --man=no "$unit" || fail 'the unit does not verify'
else
  printf 'skip: systemd-analyze not installed\n'
fi

if [[ -n $real_model && -n $real_python ]]; then
  cat >"$test_root/bin/wav-recorder" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$$" "$*" >>"$RECORDER_LOG"
exec python3 -c '
import sys, time, wave
with wave.open(sys.argv[1]) as w:
    pcm = w.readframes(w.getnframes())
start, step = time.monotonic(), 3200
for i in range(0, len(pcm), step):
    sys.stdout.buffer.write(pcm[i:i + step]); sys.stdout.buffer.flush()
    time.sleep(max(0, start + (i + step) / 32000 - time.monotonic()))
while True:
    sys.stdout.buffer.write(bytes(step)); sys.stdout.buffer.flush(); time.sleep(0.1)
' "$REAL_WAV"
SH
  chmod +x "$test_root/bin/wav-recorder"
  REAL_WAV=$real_model/test_wavs/0.wav VOICE_CAPTIONS_ENGINE=sherpa VOICE_CAPTIONS_MODEL_DIR=$real_model \
    VOICE_CAPTIONS_RECORDER=$test_root/bin/wav-recorder start_daemon "$real_python"
  report 900 armed
  python3 "$vc" watch --until-note '' --timeout 30 >/dev/null || fail 'the real model did not load'
  watcher "$test_root/real"
  report '900 listening alsa_input.test'
  sleep 7.5
  report 900 typing
  wait_for "$test_root/real" '"phase":"typing"'
  # TERM while a decode may still run: onnxruntime must not abort the exit.
  stop_daemon
  python3 - "$test_root/real" <<'PY' || fail 'the real engine did not caption the words before typing'
import json, re, sys
heard = [re.sub(r"[^a-z ]", "", e["committed"].lower()) for e in map(json.loads, open(sys.argv[1]))
         if e.get("phase") == "listening"]
assert any("after early nightfall the yellow lamps" in h for h in heard), heard[-1:]
PY
  printf 'real engine: ok\n'
else
  printf 'skip: real speech model (set VOICE_CAPTIONS_REAL_MODEL_DIR and VOICE_CAPTIONS_PYTHON)\n'
fi

# Hyprland sessions here never reach graphical-session.target, so login starts
# the service from autostart, and only when the menu enabled it.
grep -Fq 'systemctl --user -q is-enabled voice-captions.service && systemctl --user start --no-block voice-captions.service' \
  "$repo_root/hypr/.config/hypr/conf/autostart.lua" || fail 'login does not start enabled live captions'

printf 'voice captions: ok\n'
