"use strict";

const logic = require(process.argv[2]);

function ws(id, windows) {
  return { id, toplevels: { values: Array.from({ length: windows }, () => ({})) } };
}
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
function ids(list, focused) {
  return JSON.stringify(logic.visibleIds(list, focused));
}

// The live session that exposed the bug: windows on 1-4, 6, 7, 9, 11 and 17,
// focus on 1. Every one gets a badge; empty 5 and 8 stay hidden.
const live = [1, 2, 3, 4, 6, 7, 9, 11, 17].map(id => ws(id, 1));
assert(ids(live, 1) === "[1,2,3,4,6,7,9,11,17]", "every occupied workspace shows: " + ids(live, 1));

// Out-of-order input still comes back ascending by number, not by string.
assert(ids([ws(17, 1), ws(2, 1), ws(11, 1)], 2) === "[2,11,17]", "ids sort numerically");

// The focused workspace shows even when empty; other empty ones are hidden.
assert(ids([ws(1, 1), ws(2, 0), ws(3, 0)], 3) === "[1,3]", "focused empty stays, other empty hidden");

// Focus moving to an occupied workspace adds nothing new; to a new empty one adds it.
assert(ids([ws(1, 1), ws(2, 1)], 2) === "[1,2]", "focus on an occupied workspace");
assert(ids([ws(1, 1)], 12) === "[1,12]", "focus on a workspace Hyprland has not listed");

// Closing the last window drops the workspace; moving one adds the destination.
assert(ids([ws(1, 1), ws(2, 0)], 1) === "[1]", "emptied workspace disappears");
assert(ids([ws(1, 1), ws(14, 1)], 1) === "[1,14]", "moved window's destination appears");

// Special (scratchpad) workspaces have negative ids and never get a badge.
assert(ids([ws(1, 1), ws(-99, 1)], 1) === "[1]", "special workspaces are skipped");
assert(ids([ws(1, 1)], -99) === "[1]", "focused special workspace is skipped");

// Workspaces on another monitor are just more workspaces.
assert(ids([ws(1, 1), { ...ws(12, 1), monitor: { name: "HDMI-A-1" } }], 1) === "[1,12]",
       "other-monitor occupied workspace is shown");

// No focus known yet: only occupied workspaces, nothing invented.
assert(ids([ws(11, 1)], null) === "[11]", "startup shows occupied only");
assert(ids([], null) === "[]", "nothing known, nothing shown");

// A workspace whose window list is missing counts as empty, not as a crash.
assert(ids([{ id: 5 }, ws(1, 1)], 1) === "[1]", "workspace without toplevels is treated as empty");

console.log("ok: workspaces logic");
