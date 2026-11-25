"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");

// QML needs `.pragma library` as line 1, which is not JavaScript.
const source = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library\n/, "");
const logic = { exports: {} };
new Function("module", source)(logic);
logic.initialState = logic.exports.initialState;
Object.assign(logic, logic.exports);

const line = (fields) => JSON.stringify({ type: "state", v: 1, id: "1.5", committed: "", tentative: "", note: "", ...fields });
const feed = (lines, from = logic.initialState()) => lines.reduce((state, l) => logic.receive(state, l), from);

{
  const view = logic.display(logic.initialState());
  assert.deepEqual(view, { visible: false, phase: "idle", hint: "", level: 0 }, "idle shows nothing");
}

{
  const view = logic.display(feed([line({ seq: 1, phase: "armed" })]));
  assert.deepEqual(view, { visible: true, phase: "armed", hint: "", level: 0 }, "armed shows the pill with no text");
}

{
  const state = feed([line({ seq: 2, phase: "listening", committed: "and then we can", tentative: "ship" })]);
  assert.deepEqual(logic.display(state), { visible: true, phase: "listening", hint: "", level: 0 },
    "the view carries no words");
  assert.ok(!JSON.stringify(state).includes("ship") && !JSON.stringify(state).includes("and then"),
    "the words are not kept");
}

{
  const base = feed([line({ seq: 5, phase: "listening" })]);
  const same = (l) => assert.equal(logic.receive(base, l), base, "ignored: " + l);
  same("not json");
  same("");
  same("null");
  same("[1]");
  same(line({ seq: 6, type: "final", phase: "idle" }).replace('"state"', '"final"'));
  same(line({ seq: 5, phase: "idle" }));
  same(line({ seq: 4, phase: "idle" }));
  same(line({ seq: 6, phase: "dancing" }));
  same(line({ seq: "7", phase: "idle" }));
  same(line({ phase: "idle" }));
  const next = logic.receive(base, line({ seq: 6, phase: "typing", extra: 1 }));
  assert.equal(next.phase, "typing", "unknown keys are ignored, the line is accepted");
}

{
  const state = feed([line({ seq: 9, phase: "listening" }), "{bad"]);
  assert.equal(state.seq, 9, "junk between good lines changes nothing");
  const reset = logic.disconnected(state);
  assert.deepEqual(reset, logic.initialState());
  assert.equal(logic.display(reset).visible, false, "disconnected hides");
  const again = logic.receive(reset, line({ seq: 1, phase: "armed" }));
  assert.equal(again.phase, "armed", "seq restarts after a reconnect");
}

{
  const notes = { loading: "Loading speech model…", "no-audio": "No microphone audio", "engine-failed": "Live captions unavailable" };
  let seq = 0;
  for (const [note, hint] of Object.entries(notes)) {
    const view = logic.display(feed([line({ seq: ++seq, phase: "listening", note, committed: "spoken words" })]));
    assert.equal(view.hint, hint);
    assert.equal(view.visible, true);
  }
  assert.equal(logic.display(feed([line({ seq: 1, phase: "listening", note: "mystery" })])).hint, "", "an unknown note has no hint");
  assert.equal(logic.display(feed([line({ seq: 1, phase: "idle", note: "loading" })])).hint, "", "idle never hints");
}

{
  const view = logic.display(feed([line({ seq: 1, phase: "typing", committed: "final words" })]));
  assert.deepEqual(view, { visible: true, phase: "typing", hint: "", level: 0 });
}

{
  const level = (id, value) => JSON.stringify({ type: "level", v: 1, id, level: value });
  const listening = feed([line({ seq: 1, phase: "listening" })]);
  assert.equal(logic.display(listening).level, 0, "the meter starts flat");

  const loud = logic.receive(listening, level("1.5", 0.6));
  assert.equal(logic.display(loud).level, 0.6, "a level for this session moves the meter");
  assert.equal(loud.seq, 1, "a level carries no seq");

  assert.equal(logic.receive(loud, level("1.5", 0.6)), loud, "an unchanged level is a no-op");
  assert.equal(logic.receive(loud, level("9.9", 0.9)), loud, "another session's level is ignored");
  assert.equal(logic.receive(loud, level("1.5", "loud")), loud, "a non-number level is ignored");
  assert.equal(logic.display(logic.receive(loud, level("1.5", 7))).level, 1, "levels clamp to 1");
  assert.equal(logic.display(logic.receive(loud, level("1.5", -2))).level, 0, "levels clamp to 0");

  const kept = logic.receive(loud, line({ seq: 2, phase: "listening", committed: "hello there" }));
  assert.equal(logic.display(kept).level, 0.6, "a new state for the same session keeps the level");

  const typing = logic.receive(kept, line({ seq: 3, phase: "typing" }));
  assert.equal(logic.display(typing).level, 0, "typing flattens the meter");
  assert.equal(logic.receive(typing, level("1.5", 0.8)), typing, "a late level after listening is ignored");

  const armed = feed([line({ seq: 1, phase: "armed" })]);
  assert.equal(logic.receive(armed, level("1.5", 0.8)), armed, "no level before listening");

  const next = logic.receive(loud, JSON.stringify({ type: "state", v: 1, seq: 2, id: "2.5", phase: "listening", committed: "", tentative: "", note: "" }));
  assert.equal(logic.display(next).level, 0, "a new session starts flat");
}

process.stdout.write("voice-caption logic: ok\n");
