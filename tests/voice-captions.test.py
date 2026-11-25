#!/usr/bin/env python3
"""Pure tests for voice-captions: the session reducer, transcript folding,
the control-line parser, event snapshots, subscribers and the decoder."""

import importlib.machinery
import importlib.util
import json
import math
from array import array
import socket
import sys
import threading
import time
from pathlib import Path

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parent.parent / "systemd/.local/bin/voice-captions"
loader = importlib.machinery.SourceFileLoader("voice_captions", str(SCRIPT))
spec = importlib.util.spec_from_loader("voice_captions", loader)
vc = importlib.util.module_from_spec(spec)
sys.modules["voice_captions"] = vc
loader.exec_module(vc)

from dataclasses import replace  # noqa: E402

failures = 0


def check(name, condition, detail=""):
    global failures
    if condition:
        print(f"ok   {name}")
    else:
        failures += 1
        print(f"FAIL {name} {detail}")


State, Transcript, Commit, Revise = vc.State, vc.Transcript, vc.Commit, vc.Revise
Report, Updates, Tick = vc.Report, vc.Updates, vc.Tick
StartRecorder, StopRecorder, Flush, Publish = vc.StartRecorder, vc.StopRecorder, vc.Flush, vc.Publish
URGENT, LATER = Publish(urgent=True), Publish(urgent=False)

INF = float("inf")
text = Transcript("hello ", "wor")
idle = State()
armed = State(phase="armed", id="10", deadline=5)
listening = State(phase="listening", id="10", source="mic", transcript=text, engine="ready", deadline=600)
typing = replace(listening, phase="typing", deadline=60)
idle10 = State(id="10", engine="ready")

# (name, state, input, now, expected state, expected effects)
transitions = [
    ("first armed report", idle, Report("10", "armed"), 0, armed, [URGENT]),
    ("armed to listening starts the recorder", armed, Report("10", "listening", "mic"), 1,
     replace(armed, phase="listening", source="mic", deadline=601), [StartRecorder("10", "mic"), URGENT]),
    ("words while listening publish coalesced", listening, Updates("10", (Commit("world "), Revise(""))), 2,
     replace(listening, transcript=Transcript("hello world ", "")), [LATER]),
    ("an update that changes nothing publishes nothing", listening, Updates("10", (Revise("wor"),)), 2,
     listening, []),
    ("typing stops the recorder and flushes", listening, Report("10", "typing"), 3,
     replace(listening, phase="typing", deadline=63), [StopRecorder(), Flush("10"), URGENT]),
    ("flushed words still land while typing", typing, Updates("10", (Commit("wor"), Revise(""))), 4,
     replace(typing, transcript=Transcript("hello wor", "")), [LATER]),
    ("idle ends the session and forgets its text", typing, Report("10", "idle"), 5, idle10, [URGENT]),
    ("listening straight to idle stops the recorder", listening, Report("10", "idle"), 5, idle10,
     [StopRecorder(), URGENT]),
    ("armed to typing never flushes", armed, Report("10", "typing"), 1,
     replace(armed, phase="typing", deadline=61), [URGENT]),
    ("a dead recorder notes no-audio and keeps listening", listening, vc.RecorderExited("10"), 6,
     replace(listening, no_audio=True), [URGENT]),
    ("a second recorder exit is a no-op", replace(listening, no_audio=True), vc.RecorderExited("10"), 6,
     replace(listening, no_audio=True), []),
    ("an old session's recorder exit is a no-op", listening, vc.RecorderExited("9"), 6, listening, []),
    ("engine failure while listening publishes", listening, vc.EngineFailed(), 6,
     replace(listening, engine="failed"), [URGENT]),
    ("engine ready while armed publishes", armed, vc.EngineReady(), 1, replace(armed, engine="ready"), [URGENT]),
    ("engine ready while idle stays quiet", idle, vc.EngineReady(), 1, replace(idle, engine="ready"), []),
    ("a newer id pre-empts a running session", listening, Report("11", "armed"), 7,
     State(phase="armed", id="11", engine="ready", deadline=12), [StopRecorder(), URGENT]),
    ("a newer id may start straight at listening", idle10, Report("11", "listening", "usb"), 7,
     State(phase="listening", id="11", source="usb", engine="ready", deadline=607),
     [StartRecorder("11", "usb"), URGENT]),
    ("ids compare as numbers, not strings", replace(armed, id="99.9"), Report("100", "armed"), 1,
     replace(armed, id="100", deadline=6), [URGENT]),
    ("an older id is ignored", listening, Report("9.999999", "typing"), 8, listening, []),
    ("an older id by string order is still older", replace(armed, id="100"), Report("99.9", "listening", "mic"), 1,
     replace(armed, id="100"), []),
    ("a repeated report is ignored", listening, Report("10", "listening", "other"), 8, listening, []),
    ("an out-of-order earlier phase is ignored", typing, Report("10", "listening", "mic"), 8, typing, []),
    ("armed after listening is ignored", listening, Report("10", "armed"), 8, listening, []),
    ("a late report for a finished session is ignored", idle10, Report("10", "typing"), 8, idle10, []),
    ("an old session's words are ignored", listening, Updates("9", (Commit("stale"),)), 8, listening, []),
    ("words before listening are ignored", armed, Updates("10", (Commit("early"),)), 1, armed, []),
    ("before the armed deadline nothing happens", armed, Tick(), 4.99, armed, []),
    ("the armed deadline returns to idle", armed, Tick(), 5, State(id="10"), [URGENT]),
    ("the listening deadline stops the recorder", listening, Tick(), 600, idle10, [StopRecorder(), URGENT]),
    ("the typing deadline returns to idle", typing, Tick(), 60, idle10, [URGENT]),
    ("idle has no deadline", idle10, Tick(), 1e12, idle10, []),
]
for name, state, inp, now, want_state, want_effects in transitions:
    got_state, got_effects = vc.step(state, inp, now)
    check(f"step: {name}", (got_state, got_effects) == (want_state, want_effects),
          f"\n  got  {got_state} {got_effects}\n  want {want_state} {want_effects}")

custom = {"armed": 1.0, "listening": 2.0, "typing": 3.0}
state, _ = vc.step(State(), Report("1", "armed"), 0, custom)
check("step: deadlines come from the limits it is given", state.deadline == 1.0, str(state))


def notes(**fields):
    return vc.snapshot(State(**fields), 1)["note"]


check("note: loading while the model loads", notes(phase="armed", id="1") == "loading")
check("note: none once the model is ready", notes(phase="listening", id="1", engine="ready") == "")
check("note: no-audio after the recorder died",
      notes(phase="listening", id="1", engine="ready", no_audio=True) == "no-audio")
check("note: engine-failed wins", notes(phase="listening", id="1", engine="failed", no_audio=True) == "engine-failed")
check("note: idle never carries a note", notes(engine="failed") == "")


def fold(updates):
    transcript, committed_seen = Transcript(), []
    for update in updates:
        transcript = transcript.apply(update)
        committed_seen.append(transcript.committed)
    grows = all(later.startswith(earlier) for earlier, later in zip(committed_seen, committed_seen[1:]))
    return transcript, grows


sherpa_stream = [Commit("After"), Commit(" ear"), Commit("ly nightfall"), Commit(", the"), Commit(" yellow lamps")]
result, grows = fold(sherpa_stream)
check("fold: sherpa-shaped commits append and never shrink",
      result == Transcript("After early nightfall, the yellow lamps", "") and grows, str(result))

moonshine_stream = [Revise("hel"), Revise("hello wor"), Revise("hello world"), Commit("hello world "),
                    Revise(""), Revise("and the"), Revise("and then"), Commit("and then"), Revise("")]
result, grows = fold(moonshine_stream)
check("fold: moonshine-shaped revisions settle into committed text",
      result == Transcript("hello world and then", "") and grows, str(result))
mid, _ = fold(moonshine_stream[:3])
check("fold: a revising engine's line stays tentative until it commits", mid == Transcript("", "hello world"), str(mid))

engine = vc.FakeEngine()
transcript, committed_seen = Transcript(), []
for _ in range(7):
    for update in engine.feed(b"\0" * (vc.FAKE_WORD_BYTES // 2)):
        transcript = transcript.apply(update)
    committed_seen.append(transcript.committed)
check("fake engine: half a word is tentative", transcript == Transcript("word1 word2 word3 ", "word4"), str(transcript))
for update in engine.flush():
    transcript = transcript.apply(update)
check("fake engine: flush commits the tentative tail", transcript == Transcript("word1 word2 word3 word4", ""),
      str(transcript))
check("fake engine: committed only grows",
      all(b.startswith(a) for a, b in zip(committed_seen, committed_seen[1:])))

def pcm(samples):
    return array("h", samples).tobytes()


def sine(rms_db, n=800):
    peak = 32768 * 10 ** (rms_db / 20) * math.sqrt(2)
    return pcm(round(peak * math.sin(2 * math.pi * 440 * i / vc.SAMPLE_RATE)) for i in range(n))


check("level: silence is 0", vc.level_of(pcm([0] * 800)) == 0.0)
check("level: nothing is 0", vc.level_of(b"") == 0.0)
check("level: full scale is 1", vc.level_of(pcm([32767, -32768] * 400)) == 1.0, str(vc.level_of(pcm([32767, -32768] * 400))))
check("level: a -30 dBFS sine reads about 0.5", abs(vc.level_of(sine(-30)) - 0.5) <= 0.01, str(vc.level_of(sine(-30))))
check("level: a -6 dBFS sine reads about 0.9", abs(vc.level_of(sine(-6)) - 0.9) <= 0.01, str(vc.level_of(sine(-6))))
check("level: below -60 dB clamps to 0", vc.level_of(sine(-80)) == 0.0, str(vc.level_of(sine(-80))))
check("level: a trailing half sample is ignored", vc.level_of(sine(-30) + b"\x7f") == vc.level_of(sine(-30)))

valid = {
    "1764069000.123456 armed": Report("1764069000.123456", "armed"),
    "5 idle": Report("5", "idle"),
    "5.1 typing": Report("5.1", "typing"),
    "5.1 listening alsa_input.usb-Foo_Bar-00.analog-stereo":
        Report("5.1", "listening", "alsa_input.usb-Foo_Bar-00.analog-stereo"),
}
for line, report in valid.items():
    check(f"parse: accepts {line!r}", vc.parse_report(line) == report, str(vc.parse_report(line)))
junk = ["", "armed", "abc armed", "1 armed extra", "1 listening", "1 listening bad;src", "1 typing ",
        " 1 typing", "1  armed", "-1 armed", "1.2.3 armed", "1. armed", "1 sleeping", "1 ARMED",
        "１ armed", "1 armed\r", "1 listening mic other", "1 listening " + "a" * 300,
        "1" * 21 + " armed", "{\"phase\":\"armed\"}"]
for line in junk:
    check(f"parse: rejects {line[:40]!r}", vc.parse_report(line) is None)

words = " ".join(f"word{n:03d}" for n in range(100))
capped = vc.tail(words)
check("tail: short text is untouched", vc.tail("a few words") == "a few words")
check("tail: long text keeps at most 600 characters", len(capped) <= 600 and len(words) > 600, str(len(capped)))
check("tail: the cut lands on a word boundary",
      words.endswith(capped) and words[-len(capped) - 1] == " " and capped.startswith("word"), capped[:20])
check("tail: a space right before the cut keeps the whole window", vc.tail("aaa " + "b" * 600) == "b" * 600)
check("tail: one giant word is cut hard", vc.tail("z" * 1000) == "z" * 600)

event = vc.snapshot(State(phase="listening", id="7.5", engine="ready",
                          transcript=Transcript(words, "line\nbreak \"quoted\"")), 41)
check("snapshot: has exactly the wire keys",
      list(event) == ["type", "v", "seq", "id", "phase", "committed", "tentative", "note"], str(list(event)))
check("snapshot: caps the committed tail", event["committed"] == capped)
line = vc.encode(event)
check("snapshot: encodes as one NDJSON line", line.endswith(b"\n") and line.count(b"\n") == 1
      and json.loads(line) == event)
check("snapshot: idle shows the id and no text",
      vc.snapshot(State(id="9"), 3) == {"type": "state", "v": 1, "seq": 3, "id": "9", "phase": "idle",
                                         "committed": "", "tentative": "", "note": ""})

stalled, peer = socket.socketpair()
stalled.setblocking(False)
subscriber = vc.Subscriber(stalled)
chunk = b"x" * 1000 + b"\n"
offered, started = 0, time.monotonic()
while subscriber.offer(chunk):
    offered += len(chunk)
    if offered > 64 * 1024 * 1024:
        break
check("subscriber: a reader that never reads is dropped once 64 KB back",
      len(subscriber.pending) > vc.SUBSCRIBER_BUFFER_MAX and offered < 16 * 1024 * 1024,
      f"pending={len(subscriber.pending)} offered={offered}")
check("subscriber: offering never blocks", time.monotonic() - started < 2)
stalled.close()
peer.close()

reader_end, peer = socket.socketpair()
reader_end.setblocking(False)
subscriber = vc.Subscriber(reader_end)
received = 0
ok = True
for _ in range(500):
    ok = ok and subscriber.offer(chunk)
    received += len(peer.recv(1 << 20))
check("subscriber: a reader that keeps up gets every line", ok and received == 500 * len(chunk), str(received))
reader_end.close()
peer.close()


def run_decoder(load, feed):
    posted, done = [], threading.Event()

    def post(inp):
        posted.append(inp)
        if isinstance(inp, (vc.EngineFailed,)) or (isinstance(inp, Updates) and inp.updates[-1] == Revise("")):
            done.set()
    decoder = vc.Decoder(load, post)
    feed(decoder)
    done.wait(5)
    return posted


posted = run_decoder(lambda: (time.sleep(0.2), vc.FakeEngine())[1],
                     lambda d: (d.audio("1", b"\0" * (vc.FAKE_WORD_BYTES * 3 // 2)), d.flush("1")))
folded = Transcript()
for inp in posted:
    if isinstance(inp, Updates):
        for update in inp.updates:
            folded = folded.apply(update)
check("decoder: audio queued while loading is decoded after ready",
      isinstance(posted[0], vc.EngineReady) and folded == Transcript("word1 word2", ""), f"{posted} {folded}")


def broken():
    raise RuntimeError("no model")


posted = run_decoder(broken, lambda d: d.audio("1", b"\0" * 10))
check("decoder: a failed load reports engine-failed", posted == [vc.EngineFailed()], str(posted))

print(f"{failures} failed" if failures else "voice-captions: ok")
sys.exit(1 if failures else 0)
