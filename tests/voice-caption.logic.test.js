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
  const idle = logic.initialState();
  assert.equal(logic.display(idle, 100).visible, false, "idle shows nothing");
}

{
  const state = feed([line({ seq: 1, phase: "armed" })]);
  const view = logic.display(state, 100);
  assert.equal(view.visible, true);
  assert.equal(view.phase, "armed");
  assert.equal(view.hint, "Listening…", "armed shows the placeholder");
  assert.equal(view.settled + view.pending, "");
}

{
  const state = feed([line({ seq: 2, phase: "listening", committed: "and then we can", tentative: "ship" })]);
  const view = logic.display(state, 100);
  assert.equal(view.settled, "and then we can ", "the joining space stays with the committed run");
  assert.equal(view.pending, "ship");
  assert.equal(view.hint, "");
}

{
  const base = feed([line({ seq: 5, phase: "listening", committed: "hello" })]);
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
  const next = logic.receive(base, line({ seq: 6, phase: "typing", committed: "hello world", extra: 1 }));
  assert.equal(next.phase, "typing", "unknown keys are ignored, the line is accepted");
  assert.equal(next.committed, "hello world");
}

{
  const state = feed([line({ seq: 9, phase: "listening", committed: "a" }), "{bad"]);
  assert.equal(state.seq, 9, "junk between good lines changes nothing");
  const reset = logic.disconnected(state);
  assert.deepEqual(reset, logic.initialState());
  assert.equal(logic.display(reset, 100).visible, false, "disconnected hides");
  const again = logic.receive(reset, line({ seq: 1, phase: "armed" }));
  assert.equal(again.phase, "armed", "seq restarts after a reconnect");
}

{
  const words = "one two three four five six seven eight nine ten";
  const view = logic.display(feed([line({ seq: 1, phase: "listening", committed: words })]), 20);
  assert.ok(view.settled.startsWith("…"), "the head is elided: " + view.settled);
  assert.ok(view.settled.endsWith("ten"), "the newest word stays");
  assert.ok(view.settled.length <= 21);
  assert.ok(words.endsWith(" " + view.settled.slice(1)), "cut on a word boundary: " + view.settled);
}

{
  const view = logic.display(feed([line({ seq: 1, phase: "listening", committed: "short text here", tentative: "and more words follow" })]), 25);
  assert.equal(view.settled, "", "all committed text elided");
  assert.ok(view.pending.startsWith("…"), "the elision mark lands on the first visible tail: " + view.pending);
  assert.ok(view.pending.endsWith("follow"));
}

{
  const view = logic.display(feed([line({ seq: 1, phase: "listening", committed: "hello there", tentative: "my friend" })]), 100);
  assert.equal(view.settled + view.pending, "hello there my friend", "a missing space between the tails is added");
}

{
  const view = logic.display(feed([line({ seq: 1, phase: "listening", committed: "x".repeat(40) })]), 10);
  assert.equal(view.settled, "…" + "x".repeat(10), "a word longer than the limit is cut hard");
}

{
  const notes = { loading: "Loading speech model…", "no-audio": "No microphone audio", "engine-failed": "Live captions unavailable" };
  let seq = 0;
  for (const [note, hint] of Object.entries(notes)) {
    const view = logic.display(feed([line({ seq: ++seq, phase: "listening", note })]), 100);
    assert.equal(view.hint, hint);
    assert.equal(view.visible, true);
  }
}

{
  const view = logic.display(feed([line({ seq: 1, phase: "typing", committed: "final words" })]), 100);
  assert.equal(view.phase, "typing");
  assert.equal(view.settled, "final words");
  assert.equal(view.visible, true);
}

process.stdout.write("voice-caption logic: ok\n");
