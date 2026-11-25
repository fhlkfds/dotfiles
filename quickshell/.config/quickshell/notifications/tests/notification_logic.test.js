const assert = require("node:assert/strict");
const logic = require("../NotificationLogic.js");

assert.equal(logic.durationFor(0, 0, 5000, 8000, 30000), 5000);
assert.equal(logic.durationFor(1, 12000, 5000, 8000, 30000), 12000);
assert.equal(logic.durationFor(1, 90000, 5000, 8000, 30000), 30000);
assert.equal(logic.durationFor(2, 0, 5000, 8000, 30000), 0);
assert.equal(logic.durationFor(2, -1, 5000, 8000, 30000), 0);
assert.equal(logic.durationFor(2, 120000, 5000, 8000, 30000), 120000);
assert.equal(logic.durationFor(2, 1000, 5000, 8000, 30000), 1000);
assert.equal(logic.pausesOnHover(1), true);
assert.equal(logic.pausesOnHover(0), true);
assert.equal(logic.pausesOnHover(2), false);

assert.equal(logic.sanitizeBody("<b>Hello</b><br>world<img src=x>"), "Hello\nworld");
assert.equal(logic.sanitizeBody("A &amp; B"), "A & B");

assert.equal(logic.ageLabel(1000, 1000 + 59 * 1000), "now");
assert.equal(logic.ageLabel(1000, 1000 + 5 * 60 * 1000), "5m");
assert.equal(logic.ageLabel(1000, 1000 + 3 * 3600 * 1000), "3h");
assert.equal(logic.ageLabel(1000, 1000 + 2 * 86400 * 1000), "2d");
assert.equal(logic.ageLabel(5000, 1000), "now");
assert.equal(logic.ageLabel("junk", 1000), "now");
const now = Date.now();
for (const timestamp of [undefined, null, 0, -1, "junk", NaN, Infinity])
  assert.equal(logic.ageLabel(timestamp, now), "now");
for (const [seconds, label] of [[60, "1m"], [3599, "59m"], [3600, "1h"],
                               [86399, "23h"], [86400, "1d"]])
  assert.equal(logic.ageLabel(now - seconds * 1000, now), label);

const notification = {
  id: 7, appName: "NetworkManager", summary: "Wi-Fi connected", body: "Office",
  urgency: 1, expireTimeout: 1000, hints: {}
};
const snapshot = logic.snapshotOf(notification, 1234, "DP-1");
assert.equal(snapshot.key, "1234-7");
assert.equal(snapshot.glyph, "󰖩");
assert.equal(snapshot.screenName, "DP-1");
assert.equal(snapshot.actionsJson, "[]");
const screenshot = logic.snapshotOf({actions: [
  {identifier: "default", text: "Open"},
  {identifier: "edit", text: "Edit"},
  {identifier: "save", text: "Save"}
]}, 1234, "DP-1");
assert.deepEqual(JSON.parse(screenshot.actionsJson), [
  {identifier: "edit", text: "Edit"}, {identifier: "save", text: "Save"}
]);
assert.ok(logic.updateRoles().includes("actionsJson"));

assert.ok(logic.updateRoles().includes("verbatim"));

const command = 'sort < in > out && echo "&amp;"\n\n\n  indented\r\nlast  ';
const verbatim = logic.snapshotOf({id: 1, body: command, hints: {"desktop-verbatim": true}}, 1, "DP-1");
assert.equal(verbatim.verbatim, true);
assert.equal(verbatim.body, 'sort < in > out && echo "&amp;"\n\n\n  indented\nlast  ');
assert.equal(logic.snapshotOf({id: 1, body: "a\r\nb", hints: {"desktop-verbatim": true}}, 1, "").body, "a\nb");
const plain = logic.snapshotOf({id: 1, body: command, hints: {}}, 1, "DP-1");
assert.equal(plain.verbatim, false);
assert.equal(plain.body, 'sort  out && echo "&"\n  indented\nlast');
for (const hints of [undefined, {}, {"desktop-verbatim": false}, {"desktop-verbatim": "false"}]) {
  const entry = logic.snapshotOf({id: 1, body: "<b>x</b>", hints: hints}, 1, "");
  assert.equal(entry.verbatim, false);
  assert.equal(entry.body, "x");
}
assert.equal(logic.snapshotOf({id: 1, body: "x".repeat(9000), hints: {"desktop-verbatim": true}}, 1, "").body.length, 8192);
assert.equal(logic.snapshotOf({id: 1, body: "x".repeat(9000)}, 1, "").body.length, 8192);
assert.equal(logic.replacementSnapshot({id: 1, body: "a < b", hints: {"desktop-verbatim": true}}, verbatim).body, "a < b");

assert.equal(logic.shouldBypassDnd({appName: "Slack", hints: {"swaync-bypass-dnd": true}}, ["Capture"]), false);
assert.equal(logic.shouldBypassDnd({appName: "Capture", hints: {"swaync-bypass-dnd": true}}, ["Capture"]), true);
const shipped = require("../config.json").dndBypassApps;
for (const app of ["Claude Code", "Codex"])
  assert.equal(logic.shouldBypassDnd({appName: app, hints: {"desktop-bypass-dnd": true}}, shipped), true);
assert.equal(logic.shouldBypassDnd({appName: "Capture", hints: {}}, ["Capture"]), false);

assert.equal(logic.localImagePath("file:///tmp/a%20b.png"), "/tmp/a b.png");
assert.equal(logic.localImagePath("image://qsimage/1"), "");
assert.equal(logic.validEntry(snapshot), true);
assert.equal(logic.validEntry({key: "../../x", summary: "bad"}), false);

assert.equal(logic.isMediaNotification("Spotify", "/tmp/art.jpg"), true);
assert.equal(logic.isMediaNotification("spotify", "file:///tmp/art.jpg"), true);
assert.equal(logic.isMediaNotification("Spotify", ""), false);
assert.equal(logic.isMediaNotification("Slack", "/tmp/art.jpg"), false);

console.log("notification logic tests: ok");
