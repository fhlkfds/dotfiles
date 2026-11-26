#!/usr/bin/env python3
"""Pure tests for voice-captions: the session reducer with its live typist,
transcript folding, the control-line parser, event snapshots, subscribers and
the decoder."""

import asyncio
import importlib.machinery
import importlib.util
import json
import math
from array import array
import socket
import sys
import tempfile
import threading
import time
from pathlib import Path
from types import SimpleNamespace

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
StartRecorder, StopRecorder, Publish = vc.StartRecorder, vc.StopRecorder, vc.Publish
Typed, TypeFailed, Erased, Type, Erase, Ack = vc.Typed, vc.TypeFailed, vc.Erased, vc.Type, vc.Erase, vc.Ack
URGENT, LATER = Publish(urgent=True), Publish(urgent=False)

INF = float("inf")
text = Transcript("hello ", "wor")
idle = State()
armed = State(phase="armed", id="10", deadline=5)
listening = State(phase="listening", id="10", source="mic", transcript=text, engine="ready", deadline=600)
typing = replace(listening, phase="typing", deadline=60, stop="acked")
idle10 = State(id="10", engine="ready")
BOX = "0x55d0aaa"
quiet = replace(listening, target=BOX, transcript=Transcript())
K = vc.keys_for
# "hello " is with a batch; "hello " then "world " have settled.
busy = replace(listening, target=BOX, transcript=Transcript("hello world ", ""), cursor=6, inflight=6)
done = replace(listening, target=BOX, cursor=6, typed=6)
refused = replace(busy, typed=2, inflight=0, refused=True)
draining = replace(busy, phase="typing", deadline=63, stop="draining")
erasing = replace(done, phase="typing", deadline=63, stop="erasing")

# (name, state, input, now, expected state, expected effects)
transitions = [
    ("first armed report", idle, Report("10", "armed"), 0, armed, [URGENT]),
    ("armed to listening starts the recorder", armed, Report("10", "listening", "mic"), 1,
     replace(armed, phase="listening", source="mic", deadline=601), [StartRecorder("10", "mic"), URGENT]),
    ("words while listening publish coalesced", listening, Updates("10", (Commit("world "), Revise(""))), 2,
     replace(listening, transcript=Transcript("hello world ", "")), [LATER]),
    ("an update that changes nothing publishes nothing", listening, Updates("10", (Revise("wor"),)), 2,
     listening, []),
    ("typing with nothing typed stops the recorder and answers at once", listening, Report("10", "typing"), 3,
     replace(listening, phase="typing", deadline=63, stop="acked"), [StopRecorder(), Ack("10"), URGENT]),
    ("words decoded late still land while typing", typing, Updates("10", (Commit("wor"), Revise(""))), 4,
     replace(typing, transcript=Transcript("hello wor", "")), [LATER]),
    ("listening remembers the window being dictated into", armed, Report("10", "listening", "mic", BOX), 1,
     replace(armed, phase="listening", source="mic", target=BOX, deadline=601),
     [StartRecorder("10", "mic"), URGENT]),
    ("settled words are typed into the window as keys", quiet, Updates("10", (Commit("Hi? "), Revise("wor"))), 2,
     replace(quiet, transcript=Transcript("Hi? ", "wor"), cursor=4, inflight=4),
     [LATER, Type("10", BOX, (("SHIFT", "h"), ("", "i"), ("SHIFT", "slash"), ("", "space")))]),
    ("a character with no key is left out and not counted", quiet, Updates("10", (Commit("héllo ☕ "),)), 2,
     replace(quiet, transcript=Transcript("héllo ☕ ", ""), cursor=8, inflight=6), [LATER, Type("10", BOX, K("hllo  "))]),
    ("words with no key at all send nothing", quiet, Updates("10", (Commit("☕é"),)), 2,
     replace(quiet, transcript=Transcript("☕é", ""), cursor=2), [LATER]),
    ("tentative words are never typed", quiet, Updates("10", (Revise("hel"),)), 2,
     replace(quiet, transcript=Transcript("", "hel")), [LATER]),
    ("a line break is typed as a space", quiet, Updates("10", (Commit("a\nb"),)), 2,
     replace(quiet, transcript=Transcript("a\nb", ""), cursor=3, inflight=3), [LATER, Type("10", BOX, K("a b"))]),
    ("words that settle while a batch runs wait for it", replace(busy, transcript=Transcript("hello ", "")),
     Updates("10", (Commit("world "),)), 2, busy, [LATER]),
    ("a finished batch types what settled meanwhile", busy, Typed("10", 6), 2,
     replace(busy, cursor=12, typed=6), [Type("10", BOX, K("world "))]),
    ("a finished batch with nothing new rests", replace(busy, transcript=Transcript("hello ", "")), Typed("10", 6), 2,
     replace(done, transcript=Transcript("hello ", "")), []),
    ("a refused key ends live typing and the keys that landed count", busy, TypeFailed("10", 2), 2, refused, []),
    ("later words are not typed after a refusal", refused, Updates("10", (Commit("again "),)), 2,
     replace(refused, transcript=Transcript("hello world again ", "")), [LATER]),
    ("another dictation's batch result is ignored", busy, Typed("9", 6), 2, busy, []),
    ("a batch result with none running is ignored", done, Typed("10", 6), 2, done, []),
    ("stopping erases the typed words", done, Report("10", "typing"), 3, erasing,
     [StopRecorder(), Erase("10", BOX, 6), URGENT]),
    ("stopping after a refusal erases the keys that landed", refused, Report("10", "typing"), 3,
     replace(refused, phase="typing", deadline=63, stop="erasing"), [StopRecorder(), Erase("10", BOX, 2), URGENT]),
    ("stopping waits for the batch that still runs", busy, Report("10", "typing"), 3, draining,
     [StopRecorder(), URGENT]),
    ("once that batch ends its words are erased too", draining, Typed("10", 6), 3,
     replace(draining, typed=6, inflight=0, stop="erasing"), [Erase("10", BOX, 6)]),
    ("a last batch that was refused has its landed keys erased", draining, TypeFailed("10", 2), 3,
     replace(draining, typed=2, inflight=0, refused=True, stop="erasing"), [Erase("10", BOX, 2)]),
    ("a last batch that landed nothing leaves nothing to erase", draining, TypeFailed("10", 0), 3,
     replace(draining, inflight=0, refused=True, stop="acked"), [Ack("10")]),
    ("the erase is answered when it ends", erasing, Erased("10", 6), 4,
     replace(erasing, typed=0, stop="acked"), [Ack("10")]),
    ("an erase cut short is answered and what is left stays counted", erasing, Erased("10", 4), 4,
     replace(erasing, typed=2, stop="acked"), [Ack("10")]),
    ("another dictation's erase is ignored", erasing, Erased("9", 6), 4, erasing, []),
    ("words decoded late are not typed after the stop", replace(erasing, transcript=Transcript()),
     Updates("10", (Commit("late "),)), 4, replace(erasing, transcript=Transcript("late ", "")), [LATER]),
    ("a repeated typing report is answered again", typing, Report("10", "typing"), 4, typing, [Ack("10")]),
    ("a repeated typing report waits for the erase on its way", erasing, Report("10", "typing"), 4, erasing, []),
    ("a repeated typing report waits for the batch on its way", draining, Report("10", "typing"), 4, draining, []),
    ("idle leaves the typed words in the box", done, Report("10", "idle"), 5, idle10, [StopRecorder(), URGENT]),
    ("the listening deadline leaves the typed words in the box", done, Tick(), 600, idle10,
     [StopRecorder(), URGENT]),
    ("idle ends the session and forgets its text", typing, Report("10", "idle"), 5, idle10, [URGENT]),
    ("listening straight to idle stops the recorder", listening, Report("10", "idle"), 5, idle10,
     [StopRecorder(), URGENT]),
    ("armed to typing has no recorder to stop", armed, Report("10", "typing"), 1,
     replace(armed, phase="typing", deadline=61, stop="acked"), [Ack("10"), URGENT]),
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
    ("an older id changes nothing; its typing report is answered", listening, Report("9.999999", "typing"), 8,
     listening, [Ack("9.999999")]),
    ("an older id's idle report is ignored", listening, Report("9.999999", "idle"), 8, listening, []),
    ("an older id by string order is still older", replace(armed, id="100"), Report("99.9", "listening", "mic"), 1,
     replace(armed, id="100"), []),
    ("a repeated report is ignored", listening, Report("10", "listening", "other"), 8, listening, []),
    ("an out-of-order earlier phase is ignored", typing, Report("10", "listening", "mic"), 8, typing, []),
    ("armed after listening is ignored", listening, Report("10", "armed"), 8, listening, []),
    ("a late typing report for a finished session is answered", idle10, Report("10", "typing"), 8, idle10,
     [Ack("10")]),
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

state, sent, erased = replace(armed, engine="ready"), (), None
script = [Report("10", "listening", "mic", BOX), Updates("10", (Commit("Naïve "), Revise("ca"))),
          Updates("10", (Commit("café ☕? "),)), Report("10", "typing")]
for inp in script:
    pending = [inp]
    while pending:
        state, effects = vc.step(state, pending.pop(0), 1)
        for effect in effects:
            if isinstance(effect, Type):
                sent += effect.keys
                pending.append(Typed("10", len(effect.keys)))
            elif isinstance(effect, Erase):
                erased = effect.count
check("typist: a dictation sends its settled words as the keys the table has", sent == K("Nave caf ? "), repr(sent))
check("typist: the erase counts the keys sent, not the characters said",
      erased == len(sent) == 11 < len("Naïve café ☕? "), str(erased))

check("keys: a capital is SHIFT with the lowercase letter", K("aZ") == (("", "a"), ("SHIFT", "z")), repr(K("aZ")))
check("keys: a shifted sign is SHIFT with the key it shares", K('?"|~') == (
    ("SHIFT", "slash"), ("SHIFT", "apostrophe"), ("SHIFT", "backslash"), ("SHIFT", "grave")), repr(K('?"|~')))
check("keys: every printable ASCII character has a key", all(chr(code) in vc.KEYS for code in range(0x20, 0x7f)))
check("keys: every key name is plain letters and digits",
      all(mods in ("", "SHIFT") and name.isascii() and name.isalnum() for mods, name in vc.KEYS.values()))
hostile = 'a";\\]] é\n;b'
request = vc.batch(BOX, K(hostile))
commands = request.split(" ; ")
command = vc.re.compile(r'dispatch hl\.dsp\.send_shortcut\(\{ mods = "(SHIFT|)", key = "([a-z0-9]+)", '
                        r'window = "address:0x55d0aaa" \}\)')
check("batch: one dispatch per key and nothing else", all(command.fullmatch(c) for c in commands), request)
check("batch: dictated text never reaches the request",
      [command.fullmatch(c).groups() for c in commands] == list(K(hostile)) and len(commands) == 10
      and request.count(";") == len(commands) - 1 and request.isascii(), request)
check("batch: the erase is that many BackSpaces with no modifier",
      vc.batch(BOX, (vc.BACKSPACE,) * 3).split(" ; ") ==
      ['dispatch hl.dsp.send_shortcut({ mods = "", key = "BackSpace", window = "address:0x55d0aaa" })'] * 3)
check("batch: the longest batch fits one socket write",
      len(vc.batch("0x" + "f" * 16, (("SHIFT", "bracketright"),) * vc.BATCH_KEYS)) < 32 * 1024)



def press(count, script, stop_deadline=math.inf):
    """Run Daemon.press against a stand-in hyprctl; returns (keys taken, batch sizes)."""
    with tempfile.TemporaryDirectory() as tmp:
        stub = Path(tmp) / "hyprctl"
        stub.write_text("#!/usr/bin/env bash\nIFS=';' read -ra commands <<<\"$2\"\n"
                        f"echo ${{#commands[@]}} >>{tmp}/sizes\n{script}\n")
        stub.chmod(0o700)
        daemon = object.__new__(vc.Daemon)
        daemon.cfg, daemon.keyboard = SimpleNamespace(hyprctl=str(stub)), asyncio.Lock()
        daemon.helpers = {}

        async def run():
            daemon.loop = asyncio.get_running_loop()
            return await daemon.press("1.0", BOX, (vc.BACKSPACE,) * count, stop_deadline)
        taken = asyncio.run(run())
        sizes = Path(tmp) / "sizes"
        return taken, [int(size) for size in sizes.read_text().split()] if sizes.exists() else []


ok_each = "printf 'ok\\n\\n\\n%.0s' \"${commands[@]}\""
check("press: a long erase goes out in batches Hyprland reads whole", press(600, ok_each) == (600, [256, 256, 88]),
      str(press(600, ok_each)))
check("press: only the keys Hyprland took count, and a refusal ends the run",
      press(600, "printf 'ok\\n\\n\\nok\\n\\n\\nerror: key not found'") == (2, [256]))
check("press: a hyprctl that fails outright sent nothing", press(3, "exit 1") == (0, [3]))
check("press: once the stop budget is spent, no batch starts",
      press(3, ok_each, stop_deadline=-math.inf) == (0, []))

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
check("fake engine: half a word is tentative", transcript == Transcript("wörd1 wörd2 wörd3 ", "wörd4"), str(transcript))
for update in engine.flush():
    transcript = transcript.apply(update)
check("fake engine: flush commits the tentative tail", transcript == Transcript("wörd1 wörd2 wörd3 wörd4", ""),
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
    "5.1 typing 1764069001.5": Report("5.1", "typing", sent="1764069001.5"),
    "5.1 listening alsa_input.usb-Foo_Bar-00.analog-stereo":
        Report("5.1", "listening", "alsa_input.usb-Foo_Bar-00.analog-stereo"),
    "5.1 listening mic 0x55D0c0ffee": Report("5.1", "listening", "mic", "0x55D0c0ffee"),
}
for line, report in valid.items():
    check(f"parse: accepts {line!r}", vc.parse_report(line) == report, str(vc.parse_report(line)))
junk = ["", "armed", "abc armed", "1 armed extra", "1 listening", "1 listening bad;src", "1 typing ",
        " 1 typing", "1  armed", "-1 armed", "1.2.3 armed", "1. armed", "1 sleeping", "1 ARMED",
        "１ armed", "1 armed\r", "1 listening mic other", "1 listening " + "a" * 300, "1 listening mic 0x",
        "1 listening mic 0xzz", "1 listening mic 55d0", "1 listening mic 0xabc 0xdef", "1 typing 0xabc",
        "1 typing 17", "1 typing 1.5 2.5", "1 armed 1.5", "1 idle 1.5",
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
        if isinstance(inp, (vc.EngineFailed, Updates)):
            done.set()
    decoder = vc.Decoder(load, post)
    feed(decoder)
    done.wait(5)
    return posted


posted = run_decoder(lambda: (time.sleep(0.2), vc.FakeEngine())[1],
                     lambda d: d.audio("1", b"\0" * (vc.FAKE_WORD_BYTES * 3 // 2)))
folded = Transcript()
for inp in posted:
    if isinstance(inp, Updates):
        for update in inp.updates:
            folded = folded.apply(update)
check("decoder: audio queued while loading is decoded after ready",
      isinstance(posted[0], vc.EngineReady) and folded == Transcript("wörd1 ", "wörd2"), f"{posted} {folded}")


def broken():
    raise RuntimeError("no model")


posted = run_decoder(broken, lambda d: d.audio("1", b"\0" * 10))
check("decoder: a failed load reports engine-failed", posted == [vc.EngineFailed()], str(posted))

print(f"{failures} failed" if failures else "voice-captions: ok")
sys.exit(1 if failures else 0)
