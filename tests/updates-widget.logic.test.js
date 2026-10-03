"use strict";

// Run the actual QML state handlers with process/timer fixtures, without a
// desktop session or any package-manager calls.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const source = fs.readFileSync(process.argv[2], "utf8");

function fixture(stale = false) {
  const root = {
    repoCount: 2, aurCount: 3, totalCount: 5,
    repoPackages: ["repo-one", "repo-two"], aurPackages: ["aur-one"],
    stale, updating: true, updateQueued: false, lastAttempt: 0,
    minRefreshGap: 600000, notifications: [],
    notify(message) { this.notifications.push(message); }
  };
  const context = {
    root, countProc: { running: false }, updateProc: { running: false },
    countOutput: { text: "" }, countError: { text: "" },
    pollTimer: { restarts: 0, restart() { this.restarts++; } },
    console: { warn() {} }, Date
  };
  vm.createContext(context);
  for (const name of ["refresh", "update", "handleCount", "handleUpdate"]) {
    const start = source.indexOf("  function " + name + "(");
    assert.ok(start >= 0, "missing QML handler: " + name);
    const end = source.indexOf("\n  }\n", start);
    assert.ok(end >= 0);
    vm.runInContext(source.slice(start, end + 4), context);
    root[name] = context[name];
  }
  return context;
}

// The script's JSON must restore the count after a failed AUR check. A later
// failure (including malformed JSON) preserves the displayed count and names.
for (const payload of [
  { repo: 2, aur: 3, total: 5, repoPackages: ["core", "extra"], aurPackages: ["terraform-bin", "brave-bin", "held"] },
  { repo: 0, aur: 0, total: 0, repoPackages: [], aurPackages: [] }
]) {
  const { root, countOutput, pollTimer } = fixture(true);
  countOutput.text = JSON.stringify(payload) + "\n";
  root.handleCount(0);
  assert.equal(root.repoCount, payload.repo);
  assert.equal(root.aurCount, payload.aur);
  assert.equal(root.totalCount, payload.total);
  assert.equal(JSON.stringify(root.repoPackages), JSON.stringify(payload.repoPackages));
  assert.equal(JSON.stringify(root.aurPackages), JSON.stringify(payload.aurPackages));
  assert.equal(root.stale, false);
  assert.equal(pollTimer.restarts, 1);
}

for (const [code, output] of [[1, ""], [0, ""], [0, "not JSON"]]) {
  const { root, countOutput, countError, pollTimer } = fixture();
  countOutput.text = output;
  countError.text = 'unexpected yay output: error: request failed\n';
  root.handleCount(code);
  assert.equal(root.totalCount, 5);
  assert.equal(root.repoCount, 2);
  assert.equal(root.aurCount, 3);
  assert.equal(root.repoPackages.length, 2);
  assert.equal(root.aurPackages.length, 1);
  assert.equal(root.stale, true);
  assert.equal(pollTimer.restarts, 1);
}

for (const stale of [false, true]) {
  for (const scope of ["all", "repo", "aur"]) {
    const { root, pollTimer } = fixture(stale);
    root.handleUpdate(0, scope + "\n", "");
    assert.equal(root.repoCount, scope === "aur" ? 2 : 0);
    assert.equal(root.aurCount, scope === "repo" ? 3 : 0);
    assert.equal(root.totalCount, root.repoCount + root.aurCount);
    assert.equal(root.repoPackages.length, scope === "aur" ? 2 : 0);
    assert.equal(root.aurPackages.length, scope === "repo" ? 1 : 0);
    assert.equal(root.stale, stale && scope !== "all");
    assert.equal(root.updating, false);
    assert.equal(root.notifications.length, 0);
    assert.equal(pollTimer.restarts, 1);
    assert.ok(root.lastAttempt > 0);
  }
}

for (const [code, output] of [[1, "all"], [42, "aur"], [0, ""], [0, "garbage"], [0, "all\ndiagnostic"]]) {
  const { root } = fixture();
  root.handleUpdate(code, output, "failure");
  assert.equal(root.totalCount, 5, "failure or invalid scope must preserve counts");
  assert.equal(root.repoPackages.length, 2);
  assert.equal(root.aurPackages.length, 1);
  assert.equal(root.stale, true);
  assert.equal(root.updating, false);
  assert.equal(root.notifications.length, 1);
}

const queued = fixture();
queued.countProc.running = true;
queued.root.update();
assert.equal(queued.root.updateQueued, true);
assert.equal(queued.updateProc.running, false);
queued.countProc.running = false;
queued.root.update();
assert.equal(queued.updateProc.running, true);
queued.root.update();
assert.equal(queued.updateProc.running, true);

const cooldown = fixture();
cooldown.root.handleUpdate(0, "repo", "");
cooldown.root.refresh();
assert.equal(cooldown.countProc.running, false, "update completion must enforce the request floor");
cooldown.root.lastAttempt = Date.now() - cooldown.root.minRefreshGap - 1;
cooldown.root.refresh();
assert.equal(cooldown.countProc.running, true);

console.log("updates state logic: ok");
