"use strict";

const assert = require("node:assert/strict");
const logic = require(process.argv[2]);
const hold = logic.HOLD_MS;

function run(steps) {
  let state = logic.initialState();
  const shown = [];
  for (const [at, step] of steps) {
    if (step === "expire") {
      state = logic.expire(state, at);
    } else {
      const result = logic.change(state, step, at);
      state = result.state;
      if (result.shown) shown.push(at);
    }
  }
  return { state, shown };
}

const sink = (level, muted = false) => ({ kind: "volume", device: "alsa-sink", level, muted });

{
  const { state, shown } = run([[0, sink(40)]]);
  assert.equal(state.visible, false, "the first reading from a device is a baseline, not a change");
  assert.deepEqual(shown, []);
}

{
  const { state } = run([[0, sink(40)], [100, sink(45)], [100 + hold / 2, sink(50)]]);
  assert.equal(state.visible, true, "two changes inside the hold window leave one visible pill");
  assert.equal(state.level, 50, "the pill shows the latest level");
  assert.equal(state.hideAt, 100 + hold / 2 + hold, "the second change extends the deadline");
}

{
  const steps = [[0, sink(40)], [100, sink(45)], [600, sink(50)]];
  const early = run(steps.concat([[100 + hold, "expire"]])).state;
  assert.equal(early.visible, true, "a timer armed by the first press does not hide a pill a later press extended");
  const late = run(steps.concat([[600 + hold, "expire"]])).state;
  assert.equal(late.visible, false, "the pill hides once the hold after the last change has passed");
  assert.equal(late.level, 50);
}

{
  const { state } = run([[0, sink(40)], [100, sink(40, true)]]);
  assert.equal(state.visible, true, "a mute toggle alone shows the pill");
  assert.equal(logic.levelText(state.level, state.muted), "Muted");
}

{
  const { state } = run([[0, sink(40)], [100, sink(40)]]);
  assert.equal(state.visible, false, "a repeated identical reading is not a change");
}

{
  const other = { kind: "volume", device: "usb-headset", level: 70, muted: false };
  const { state } = run([[0, sink(40)], [100, other]]);
  assert.equal(state.visible, false, "switching the default sink does not show the pill");
}

{
  const unbound = { kind: "volume", device: "", level: 0, muted: false };
  const { state } = run([[0, unbound], [50, sink(40)], [100, sink(45)]]);
  assert.equal(state.visible, true, "a source becoming ready is quiet, then its changes show");
  assert.equal(state.level, 45);
  const again = run([[0, sink(40)], [50, unbound], [100, sink(45)]]).state;
  assert.equal(again.visible, false, "losing the source forgets its baseline");
}

{
  const light = (level) => ({ kind: "brightness", device: "/sys/class/backlight/intel", level, muted: false });
  const { state } = run([[0, sink(40)], [0, light(60)], [100, sink(45)], [200, light(65)]]);
  assert.equal(state.kind, "brightness", "a change of another kind takes over the same pill");
  assert.equal(state.level, 65);
}

assert.equal(logic.levelText(42.4, false), "42%");
assert.equal(logic.levelText(Number.NaN, false), "0%");

console.log("ok: osd logic");
