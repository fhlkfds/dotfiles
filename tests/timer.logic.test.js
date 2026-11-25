"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");

const logic = require(process.argv[2]
  || path.join(__dirname, "../quickshell/.config/quickshell/timer/TimerLogic.js"));

const T0 = Date.UTC(2026, 0, 15, 12, 0, 0);
const MIN = 60000;

function reduce(state, event) { return logic.reduce(state, event); }
function started(durationMs = 10 * MIN, now = T0, label = "") {
  return reduce(logic.initialState(), { type: "start", durationMs, label, now }).state;
}
function done(state = started()) {
  return reduce(state, { type: "tick", now: state.endsAt }).state;
}

// --- reduce -----------------------------------------------------------------
{
  const result = reduce(logic.initialState(), { type: "start", durationMs: 10 * MIN, label: "tea", now: T0 });
  assert.deepEqual(result.state, {
    version: 1, phase: "running", durationMs: 10 * MIN, endsAt: T0 + 10 * MIN, label: "tea", notified: false,
  });
  assert.deepEqual(result.effects, ["persist"], "start persists");
}

{
  const replaced = reduce(started(10 * MIN), { type: "start", durationMs: 5 * MIN, label: "", now: T0 + MIN });
  assert.equal(replaced.state.endsAt, T0 + 6 * MIN, "start while running replaces the timer");
  assert.equal(replaced.state.durationMs, 5 * MIN);
  const again = reduce(done(), { type: "start", durationMs: MIN, label: "", now: T0 + 20 * MIN });
  assert.equal(again.state.phase, "running", "start from done replaces the timer");
  assert.equal(again.state.notified, false, "a new timer has not alerted");
}

for (const durationMs of [0, -5, NaN, undefined, "abc", logic.MAX_MS + 1]) {
  const result = reduce(logic.initialState(), { type: "start", durationMs, label: "", now: T0 });
  assert.equal(result.state.phase, "idle", `start ignores ${String(durationMs)}`);
  assert.deepEqual(result.effects, []);
}
assert.equal(reduce(logic.initialState(), { type: "start", durationMs: logic.MAX_MS, label: "", now: T0 }).state.phase,
  "running", "exactly 24 h is allowed");
assert.equal(reduce(logic.initialState(), { type: "start", durationMs: MIN, label: "x".repeat(200), now: T0 }).state.label.length,
  60, "a label is bounded");

{
  const before = started(10 * MIN);
  const result = reduce(before, { type: "addMinute" });
  assert.equal(result.state.endsAt, before.endsAt + MIN, "addMinute moves the end time");
  assert.equal(result.state.durationMs, 11 * MIN, "addMinute grows the duration so progress stays right");
  assert.deepEqual(result.effects, ["persist"]);
  assert.equal(before.endsAt, T0 + 10 * MIN, "reduce never mutates its input");
  for (const state of [logic.initialState(), done()]) {
    const noop = reduce(state, { type: "addMinute" });
    assert.equal(noop.state, state, `addMinute is a no-op in ${state.phase}`);
    assert.deepEqual(noop.effects, []);
  }
  const nearCap = started(logic.MAX_MS - 30000);
  assert.equal(reduce(nearCap, { type: "addMinute" }).state, nearCap, "addMinute cannot pass 24 h");
}

for (const state of [started(), done()]) {
  const result = reduce(state, { type: "cancel" });
  assert.deepEqual(result.state, logic.initialState(), `cancel from ${state.phase} goes to idle`);
  assert.deepEqual(result.effects, ["persist"]);
}
assert.deepEqual(reduce(logic.initialState(), { type: "cancel" }).effects, [], "cancel when idle does nothing");

{
  const running = started(10 * MIN);
  const early = reduce(running, { type: "tick", now: running.endsAt - 1 });
  assert.equal(early.state, running, "tick before the end changes nothing");
  assert.deepEqual(early.effects, []);
  const exact = reduce(running, { type: "tick", now: running.endsAt });
  assert.equal(exact.state.phase, "done", "tick at the end finishes");
  assert.equal(exact.state.notified, true);
  assert.deepEqual(exact.effects, ["persist", "alert"], "persist comes before alert");
  const late = reduce(running, { type: "tick", now: running.endsAt + 3600 * 1000 });
  assert.equal(late.state.phase, "done", "a tick long after the end (resume from sleep) finishes");
  assert.deepEqual(late.effects, ["persist", "alert"]);
  assert.equal(late.state.durationMs, 10 * MIN, "done keeps the duration for the alert text");
  const second = reduce(exact.state, { type: "tick", now: running.endsAt + 5000 });
  assert.deepEqual(second.effects, [], "a done timer never alerts twice");
  assert.equal(reduce(logic.initialState(), { type: "tick", now: T0 }).state.phase, "idle");
  assert.equal(reduce(running, { type: "tick", now: NaN }).state, running, "tick ignores a bad clock");
}

{
  const finished = done();
  const result = reduce(finished, { type: "dismiss" });
  assert.deepEqual(result.state, logic.initialState());
  assert.deepEqual(result.effects, ["persist"]);
  const running = started();
  assert.equal(reduce(running, { type: "dismiss" }).state, running, "dismiss leaves a running timer alone");
  assert.deepEqual(reduce(logic.initialState(), { type: "dismiss" }).effects, []);
  assert.deepEqual(reduce(running, { type: "bogus" }).effects, [], "unknown events are ignored");
}

// --- restore ----------------------------------------------------------------
{
  for (const text of ["", "not json", "null", "[]", "42", "{}", '{"version":2,"phase":"running"}',
      '{"version":1,"phase":"sleeping"}', undefined]) {
    const result = logic.restore(text, T0);
    assert.deepEqual(result.state, logic.initialState(), `unreadable file gives idle: ${text}`);
    assert.deepEqual(result.effects, []);
  }
  const bad = { version: 1, phase: "running", durationMs: 600000, endsAt: T0 + 5000, label: "", notified: false };
  for (const patch of [{ durationMs: 0 }, { durationMs: "x" }, { durationMs: logic.MAX_MS + 1 }, { endsAt: 0 },
      { endsAt: "later" }, { endsAt: T0 + logic.MAX_MS + 1 }]) {
    assert.deepEqual(logic.restore(JSON.stringify({ ...bad, ...patch }), T0).state, logic.initialState(),
      `bad field gives idle: ${JSON.stringify(patch)}`);
  }
  assert.deepEqual(logic.restore(JSON.stringify(logic.initialState()), T0).state, logic.initialState());

  const running = started(10 * MIN, T0, "tea");
  const live = logic.restore(JSON.stringify(running), T0 + MIN);
  assert.deepEqual(live.state, running, "a running timer with time left comes back as it was");
  assert.deepEqual(live.effects, []);

  const pastDue = logic.restore(JSON.stringify(running), running.endsAt + 1);
  assert.equal(pastDue.state.phase, "done", "a past-due running timer comes back as done");
  assert.equal(pastDue.state.notified, true);
  assert.deepEqual(pastDue.effects, ["persist", "alert"], "and alerts once");
  assert.equal(pastDue.state.label, "tea");
  const atEnd = logic.restore(JSON.stringify(running), running.endsAt);
  assert.equal(atEnd.state.phase, "done", "now == endsAt counts as past due, like tick");

  const reloaded = logic.restore(JSON.stringify(pastDue.state), running.endsAt + 99999);
  assert.equal(reloaded.state.phase, "done");
  assert.deepEqual(reloaded.effects, [], "a done timer that already alerted never alerts again");

  const unnotified = logic.restore(JSON.stringify({ ...pastDue.state, notified: false }), running.endsAt + 5);
  assert.deepEqual(unnotified.effects, ["persist", "alert"], "a done timer that never alerted alerts once");
  assert.equal(unnotified.state.notified, true);

  const runningNotified = logic.restore(JSON.stringify({ ...running, notified: true }), running.endsAt + 5);
  assert.deepEqual(runningNotified.effects, ["persist"], "an already-notified past-due timer persists without alerting");

  const wild = logic.restore(JSON.stringify({ ...running, label: 42, extra: "ignored" }), T0 + MIN);
  assert.equal(wild.state.label, "", "a non-string label is dropped");
  assert.equal(Object.hasOwn(wild.state, "extra"), false, "unknown keys are dropped");
}

// --- derived values ---------------------------------------------------------
{
  const running = started(10 * MIN);
  assert.equal(logic.remainingMs(running, T0 + 4 * MIN), 6 * MIN);
  assert.equal(logic.remainingMs(running, T0 + 99 * MIN), 0, "remaining never goes negative");
  assert.equal(logic.remainingMs(logic.initialState(), T0), 0);
  assert.equal(logic.progress(running, T0), 0);
  assert.equal(logic.progress(running, T0 + 5 * MIN), 0.5);
  assert.equal(logic.progress(running, T0 + 50 * MIN), 1);
  assert.equal(logic.progress(logic.initialState(), T0), 0);
  assert.equal(logic.nextTickDelay(running, T0), 1002, "a whole-second remainder ticks one second later");
  assert.equal(logic.nextTickDelay(running, T0 + 500), 502, "a part-second remainder ticks on the boundary");
  assert.equal(logic.nextTickDelay(running, T0 + 10 * MIN), 16, "an expired timer ticks at once");
}

// --- parseDuration ----------------------------------------------------------
{
  const accepted = [
    ["10", 10 * MIN], ["1", MIN], ["010", 10 * MIN], ["90s", 90000], ["7m30s", 450000], ["1h", 3600000],
    ["1h30m", 5400000], ["1h30m15s", 5415000], ["45m", 45 * MIN], ["2H", 7200000], ["7M30S", 450000],
    ["  7m 30s ", 450000], ["7:30", 450000], ["0:45", 45000], ["90:00", 90 * MIN], ["24h", logic.MAX_MS],
    ["1440", logic.MAX_MS], ["1440m", logic.MAX_MS], ["86400s", logic.MAX_MS], ["24:00", 24 * MIN],
    ["1s", 1000], ["0h5m", 5 * MIN],
  ];
  for (const [text, ms] of accepted) {
    assert.deepEqual(logic.parseDuration(text), { ms }, `accepts ${JSON.stringify(text)}`);
  }
  const rejected = [
    "", "   ", undefined, null, "0", "0m", "0s", "0:00", "0h0m0s", "24h1s", "1441", "1441m", "100h", "86401s",
    "9".repeat(400), "abc", "m", "h30", "5x", "7m30", "1.5h", "-5", "+5", "7:5", "7:60", "7:30:15", ":30",
    "30s7m", "1h1h", "7 m 30 x",
  ];
  for (const text of rejected) {
    const result = logic.parseDuration(text);
    assert.equal(typeof result.error, "string", `rejects ${JSON.stringify(text)}`);
    assert.ok(result.error.length > 0);
    assert.equal(Object.hasOwn(result, "ms"), false);
  }
}

// --- formatting -------------------------------------------------------------
{
  const formatted = [
    [598000, "9:58"], [5000, "0:05"], [3723000, "1:02:03"], [0, "0:00"], [-5, "0:00"], [450000, "7:30"],
    [449001, "7:30"], [449000, "7:29"], [1, "0:01"], [600000, "10:00"], [3600000, "1:00:00"],
    [86400000, "24:00:00"], [59999, "1:00"],
  ];
  for (const [ms, text] of formatted) assert.equal(logic.formatRemaining(ms), text, `formatRemaining(${ms})`);

  const described = [
    [450000, "7 min 30 s"], [600000, "10 min"], [3600000, "1 h"], [5400000, "1 h 30 min"], [90000, "1 min 30 s"],
    [45000, "45 s"], [3605000, "1 h 5 s"], [0, "0 s"], [86400000, "24 h"], [1499, "1 s"],
  ];
  for (const [ms, text] of described) assert.equal(logic.describe(ms), text, `describe(${ms})`);

  const local = new Date(2026, 0, 15, 15, 2, 30).getTime();
  assert.equal(logic.clockTime(local), "15:02:30");
  assert.equal(logic.clockTime(new Date(2026, 0, 15, 9, 5, 7).getTime()), "09:05:07");
}

// --- config -----------------------------------------------------------------
{
  const defaults = { presets: [5, 10, 25, 60], sound: logic.DEFAULT_SOUND };
  assert.deepEqual(logic.normalizeConfig(undefined), defaults);
  assert.deepEqual(logic.normalizeConfig(null), defaults);
  assert.deepEqual(logic.normalizeConfig("text"), defaults);
  assert.deepEqual(logic.normalizeConfig({ presets: [3, 15], sound: "/tmp/ding.oga" }), { presets: [3, 15], sound: "/tmp/ding.oga" });
  for (const presets of [[], [0], [-1], [1.5], ["5"], [1441], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], "5", {}]) {
    assert.deepEqual(logic.normalizeConfig({ presets }).presets, defaults.presets, `bad presets fall back: ${JSON.stringify(presets)}`);
  }
  assert.equal(logic.normalizeConfig({ sound: "" }).sound, logic.DEFAULT_SOUND);
  assert.equal(logic.normalizeConfig({ sound: 7 }).sound, logic.DEFAULT_SOUND);
  const shipped = JSON.parse(require("node:fs").readFileSync(
    path.join(__dirname, "../quickshell/.config/quickshell/timer/config.json"), "utf8"));
  assert.deepEqual(logic.normalizeConfig(shipped), shipped, "the shipped config.json is valid as written");
}

console.log("ok: timer logic");
