"use strict";

// Usage: node tests/bluetooth-battery-alerts.logic.test.js [path/to/BluetoothBatteryAlerts.js]
const path = require("path");
const logic = require(process.argv[2] || path.join(__dirname,
  "../quickshell/.config/quickshell/BluetoothBatteryAlerts.js"));

function assert(condition, message) {
  if (!condition)
    throw new Error(message);
}

function device(battery, connected = true, address = "AA:BB:CC:DD:EE:01") {
  return { address, name: "AirPods", icon: "audio-headphones", connected, battery };
}

// Each step is [ok, devices]; returns the alerts as "level:percent" strings.
function run(steps) {
  let state = {};
  const seen = [];
  for (const [ok, devices] of steps) {
    const result = logic.update(state, ok, devices);
    state = result.state;
    seen.push(...result.alerts.map(a => `${a.level}:${a.battery}`));
  }
  return seen.join(",");
}

const drain = run([
  [true, [device(40)]],
  [true, [device(11)]],
  [true, [device(10)]],
  [true, [device(9)]],   // Still low: no repeat.
  [true, [device(5)]],
  [true, [device(3)]],   // Still critical: no repeat.
  [true, [device(3, false)]],
  [true, [device(-1, false)]]
]);
assert(drain === "low:10,critical:5,dead:3", `drain cycle: ${drain}`);

const toZero = run([[true, [device(8)]], [true, [device(0)]], [true, [device(0, false)]]]);
assert(toZero === "low:8,dead:0", `zero reading counts as dead once: ${toZero}`);

const cold = run([[true, [device(4)]]]);
assert(cold === "critical:4", `cold start alerts only the worst level: ${cold}`);

const wobble = run([[true, [device(10)]], [true, [device(11)]], [true, [device(10)]]]);
assert(wobble === "low:10", `a wobble around 10% alerts once: ${wobble}`);

const recharged = run([[true, [device(10)]], [true, [device(80)]], [true, [device(10)]]]);
assert(recharged === "low:10,low:10", `a recharge re-arms: ${recharged}`);

const adapterOff = run([[true, [device(4)]], [false, []], [true, [device(-1, false)]]]);
assert(adapterOff === "critical:4", `adapter off is not a death: ${adapterOff}`);

const healthyDisconnect = run([[true, [device(60)]], [true, [device(60, false)]]]);
assert(healthyDisconnect === "", `a healthy disconnect is silent: ${healthyDisconnect}`);

const unknown = run([[true, [device(-1)]], [true, [device(-1, false)]]]);
assert(unknown === "", `devices without a battery reading are ignored: ${unknown}`);

const many = logic.update({}, true, [
  device(9, true, "AA:00:00:00:00:01"),
  device(50, true, "AA:00:00:00:00:02"),
  device(2, true, "AA:00:00:00:00:03")
]);
assert(many.alerts.map(a => a.address).join(",") === "AA:00:00:00:00:01,AA:00:00:00:00:03",
       "devices are tracked independently");

assert(logic.message({ level: "low", name: "AirPods", battery: 10 }).title === "AirPods at 10%",
       "low alert title");
assert(logic.message({ level: "critical", name: "MX Keys", battery: 5 }).title === "MX Keys at 5%",
       "critical alert title");
assert(logic.message({ level: "dead", name: "AirPods", battery: 0 }).title === "AirPods died",
       "dead alert title");

console.log("ok: bluetooth battery alert fixtures");
