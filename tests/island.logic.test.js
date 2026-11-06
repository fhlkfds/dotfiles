"use strict";

const assert = require("node:assert/strict");
const logic = require(process.argv[2]);

const kinds = logic.kindTable({});
const track = (title) => ({ kind: "media", glyph: "m", title, body: "" });
const titles = (queue) => [queue.current && queue.current.title].concat(queue.pending.map((g) => g.title));

assert.equal(kinds.notification, undefined, "notifications are not an island kind");
assert.deepEqual(kinds.media, { holdMs: 3500, priority: 1 }, "media defaults");
const tuned = logic.kindTable({ media: { holdMs: 1200, priority: 4 } });
assert.equal(tuned.media.holdMs, 1200, "config overrides a hold time");
assert.equal(tuned.media.priority, 4, "config overrides a priority");
assert.equal(logic.kindTable({ media: { holdMs: "soon" } }).media.holdMs, 3500, "a malformed hold time keeps the default");
assert.equal(logic.kindTable({ media: { holdMs: 0 } }).media.holdMs, 3500, "a zero hold would never show; default kept");

let q = logic.emptyQueue();
assert.equal(logic.holdFor(q, kinds), 0, "an empty queue holds nothing");
q = logic.enqueue(q, track("A"), kinds);
assert.deepEqual(titles(q), ["A"], "the first glance shows at once");
assert.equal(logic.holdFor(q, kinds), 3500, "hold time comes from the kind table");

q = logic.enqueue(q, track("B"), kinds);
assert.deepEqual(titles(q), ["B"], "a newer track replaces the one on screen");

const two = { media: { holdMs: 3500, priority: 1 }, other: { holdMs: 1000, priority: 2 } };
const other = (title) => ({ kind: "other", glyph: "o", title, body: "" });
q = logic.enqueue(q, other("n1"), two);
q = logic.enqueue(q, other("n2"), two);
assert.deepEqual(titles(q), ["B", "n2"], "a newer glance of one kind replaces the queued one");

q = logic.enqueue(logic.enqueue(logic.enqueue(logic.emptyQueue(), other("n"), two), track("t"), two), track("u"), two);
assert.deepEqual(titles(q), ["n", "u"], "waiting glances coalesce per kind, so the queue is bounded by the kind count");

q = logic.enqueue(logic.enqueue(logic.emptyQueue(), other("n"), two), track("t"), two);
q = logic.enqueue(q, other("n-late"), two);
assert.deepEqual(titles(q), ["n-late", "t"], "a same-kind glance refreshes the one on screen rather than queueing");

q = logic.enqueue(logic.enqueue(logic.emptyQueue(), track("on screen"), two), other("n"), two);
assert.deepEqual(titles(q), ["on screen", "n"], "a waiting glance never pre-empts the one on screen");

const three = { a: { holdMs: 1000, priority: 1 }, b: { holdMs: 1000, priority: 3 }, c: { holdMs: 1000, priority: 2 } };
q = { current: { kind: "a", title: "now" }, pending: [] };
q = logic.enqueue(q, { kind: "c", title: "c" }, three);
q = logic.enqueue(q, { kind: "b", title: "b" }, three);
assert.deepEqual(titles(q), ["now", "b", "c"], "higher priority waits at the front");

assert.equal(logic.enqueue(q, { kind: "timer", title: "t" }, kinds), q, "an unknown kind is ignored");
const empty = logic.emptyQueue();
assert.equal(logic.enqueue(empty, { kind: "notification", title: "mail" }, kinds), empty,
  "a notification cannot become a glance");

q = logic.advance(logic.advance(q));
assert.deepEqual(titles(q), ["c"], "advance shows the next waiting glance");
q = logic.advance(q);
assert.equal(q.current, null, "advance past the last glance folds back to the clock");

const rest = { x: 400, width: 200 };
assert.deepEqual(logic.capsuleSpan(rest, 520, 0, 0, 2000), rest, "no glance leaves the resting capsule alone");
assert.deepEqual(logic.capsuleSpan(rest, 520, 400, 0, 2000), { x: 320, width: 400 }, "the capsule widens about the clock centre");
assert.deepEqual(logic.capsuleSpan(rest, 520, 100, 0, 2000), rest, "a narrow glance never shrinks the capsule below rest");
assert.deepEqual(logic.capsuleSpan(rest, 520, 1000, 380, 700), { x: 380, width: 280 }, "the capsule stays centred on the clock and stops at the nearer island");

console.log("island logic tests: ok");
