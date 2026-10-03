"use strict";

// Run the dashboard's holiday library (a QML .pragma library) under node.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const source = fs.readFileSync(process.argv[2], "utf8").replace(".pragma library", "");

const lib = {};
vm.createContext(lib);
vm.runInContext(source, lib);

const day = (year, name) => lib.forYear(year).find(h => h.name === name).day;

// Moving holidays, against published 2024-2027 dates.
assert.equal(day(2026, "Martin Luther King Jr. Day"), 19);
assert.equal(day(2026, "Presidents' Day"), 16);
assert.equal(day(2026, "Memorial Day"), 25);
assert.equal(day(2024, "Memorial Day"), 27);
assert.equal(day(2026, "Labor Day"), 7);
assert.equal(day(2026, "Columbus Day"), 12);
assert.equal(day(2026, "Thanksgiving"), 26);
assert.equal(day(2027, "Thanksgiving"), 25);

assert.equal(lib.nameOn(new Date(2026, 6, 4)), "Independence Day");
assert.equal(lib.nameOn(new Date(2026, 6, 5)), "");

// The countdown, including today itself and the wrap into next year.
const soon = lib.next(new Date(2026, 9, 1, 16, 45));
assert.equal(soon.name, "Columbus Day");
assert.equal(soon.days, 11);
assert.equal(lib.next(new Date(2026, 11, 25, 9)).days, 0);
assert.equal(lib.next(new Date(2026, 11, 26)).name, "New Year's Day");
assert.equal(lib.next(new Date(2026, 11, 26)).days, 6);

console.log("ok: dashboard holidays");
