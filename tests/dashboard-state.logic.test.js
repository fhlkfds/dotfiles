// Exercise the actual QML parsing functions with deterministic file fixtures.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const qs = path.join(__dirname, '../quickshell/.config/quickshell');
function functions(file) {
  const source = fs.readFileSync(path.join(qs, file), 'utf8');
  const out = [];
  for (const match of source.matchAll(/\bfunction (\w+)\([^)]*\)\s*\{/g)) {
    let end = match.index + match[0].length, depth = 1;
    while (depth && end < source.length) {
      if (source[end] === '{') depth++;
      if (source[end] === '}') depth--;
      end++;
    }
    out.push(source.slice(match.index, end));
  }
  return out.join('\n');
}
function context(file, root, extra = {}) {
  const ctx = vm.createContext({root, console, ...extra});
  // QML also exposes the object's properties as unqualified identifiers.
  for (const key of Object.keys(root))
    Object.defineProperty(ctx, key, {get: () => root[key], set: v => {root[key] = v;}, enumerable: true});
  vm.runInContext(functions(file), ctx);
  Object.assign(root, Object.fromEntries(Object.entries(ctx).filter(([, v]) => typeof v === 'function')));
  return ctx;
}
const checks = [];
function check(name, run) {
  try { run(); console.log('ok:', name); }
  catch (error) { checks.push(name); console.error('FAIL:', name, error.message.split("\n\n")[0]); }
}
const state = {active: true, nvidiaAwake: true, lastStat: [], cpuHistory: [], gpuHistory: [], historyLength: 60, cpuSeeded: false,
  coreUsage: [], netIface: '', lastNetRx: -1, lastNetMs: 0, rxRate: 0, txRate: 0,
  rxHistory: [], txHistory: [], cpuTempReported: false};
let stat = '', net = '';
const ctx = context('SysState.qml', state, {
  statFile: {reload() {}, text: () => stat},
  netFile: {reload() {}, text: () => net},
  NetworkState: {iface: 'eth0'},
});
check('CPU excludes already-accounted guest time', () => {
  const sample = text => {
    stat = text;
    if (ctx.parseCpu) ctx.parseCpu(text); else ctx.sampleCpu();
  };
  sample('cpu 100 0 0 100 0 0 0 0 100 0\ncpu0 100 0 0 100 0 0 0 0 100 0\n');
  sample('cpu 150 0 0 150 0 0 0 0 150 0\ncpu0 150 0 0 150 0 0 0 0 150 0\n');
  assert.equal(state.cpuPercent, 50);
  assert.equal(state.coreUsage[0], 0.5);
});
check('network interface changes clear old rates and histories', () => {
  Object.assign(state, {netIface: 'old0', rxRate: 999, txRate: 888, rxHistory: [999], txHistory: [888]});
  net = 'header\nheader\neth0: 200 0 0 0 0 0 0 0 100 0 0 0 0 0 0 0\n';
  if (ctx.parseNet) ctx.parseNet(net); else ctx.sampleNet();
  assert.equal(state.netIface, 'eth0');
  assert.equal(state.rxRate, 0);
  assert.equal(state.rxHistory.length, 0);
});
check('disappearing network interface clears stale readings', () => {
  net = 'header\nheader\nlo: 100 0 0 0 0 0 0 0 100 0 0 0 0 0 0 0\n';
  if (ctx.parseNet) ctx.parseNet(net); else ctx.sampleNet();
  assert.equal(state.netIface, '');
  assert.equal(state.rxTotal, 0);
});
check('NVIDIA unsupported fields cannot become NaN', () => {
  assert.equal(typeof ctx.parseNvidia, 'function');
  ctx.parseNvidia('37, 51, [N/A], [N/A], [N/A]');
  assert.equal(state.gpuReported, true);
  assert.equal(state.gpuVramTotalBytes, 0);
  assert.equal(state.gpuPowerW, -1);
  ctx.parseNvidia('[N/A], [N/A], [N/A], [N/A], [N/A]');
  assert.equal(state.gpuReported, false);
  assert.equal(state.gpuTempReported, false);
  state.nvidiaAwake = false;
  ctx.parseNvidia('37, 51, 1024, 4096, 22');
  assert.equal(state.gpuReported, false);
  state.nvidiaAwake = true;
});
check('async proc reads are parsed when loading completes', () => {
  const source = fs.readFileSync(path.join(qs, 'SysState.qml'), 'utf8');
  assert.match(source, /onLoaded:\s*root\.parseCpu\(text\(\)\)/);
  assert.doesNotMatch(source, /reload\(\)\s*\n\s*const .*File\.text\(\)/);
});
check('late async samples cannot reseed a closed dashboard', () => {
  Object.assign(state, {active: false, lastStat: [], lastNetRx: -1});
  ctx.parseCpu(stat);
  ctx.parseNet(net);
  assert.equal(state.lastStat.length, 0);
  assert.equal(state.lastNetRx, -1);
});
check('weather hour follows response timezone independently of host TZ', () => {
  const weather = {utcOffsetSeconds: -18000};
  const w = context('WeatherState.qml', weather);
  assert.equal(typeof w.hourAt, 'function');
  assert.equal(w.hourAt(Date.parse('2026-10-03T23:30:00Z')), '2026-10-03T18:00');
  weather.utcOffsetSeconds = 19800;
  assert.equal(w.hourAt(Date.parse('2026-10-03T23:30:00Z')), '2026-10-04T05:00');
  assert.equal(w.fmtTemp(null), '--°F');
  assert.equal(w.uvLabel(null), '--');
});
check('malformed weather preserves good data and reports an error', () => {
  const good = {temp: 66};
  const weather = {current: good, locationKey: 'Chicago', fetchLocationKey: 'Chicago'};
  const w = context('WeatherState.qml', weather);
  const current = {temperature_2m: 66, apparent_temperature: 65, relative_humidity_2m: 60,
    weather_code: 0, wind_speed_10m: 3, is_day: 1, uv_index: null};
  w.acceptForecast(JSON.stringify({current: {...current, temperature_2m: null}}));
  assert.equal(weather.current, good);
  assert.equal(weather.status, 'error');
  w.acceptForecast(JSON.stringify({current, hourly: {time: ['2026-10-03T18:00']}}));
  assert.equal(weather.current, good);
  assert.equal(weather.status, 'error');
  w.acceptForecast('');
  assert.equal(weather.status, 'error');
  w.acceptForecast(JSON.stringify({current, utc_offset_seconds: -18000,
    hourly: {time: ['2026-10-03T18:00', '2026-10-03T19:00'], temperature_2m: [null, 64],
      precipitation_probability: [null, null], weather_code: [0, 0]}}));
  assert.equal(weather.hourly.length, 1);
  assert.equal(weather.hourly[0].temp, 64);
  assert.equal(w.fmtPercent(weather.hourly[0].precipProb), '--');
  assert.equal(weather.utcOffsetSeconds, -18000);
  assert.equal(weather.status, 'ok');
  weather.locationKey = 'Denver';
  const previous = weather.current;
  w.acceptForecast(JSON.stringify({current: {...current, temperature_2m: 99}}));
  assert.equal(weather.current, previous);
});
check('invalid saved coordinates cannot change the location', () => {
  const w = context('WeatherState.qml', {});
  for (const latitude of [null, '', 91, NaN])
    assert.equal(w.applyLocation({latitude, longitude: 0}), false);
});
check('city search keeps populated places starting with the text, largest first', () => {
  const w = context('WeatherState.qml', {});
  const place = (name, population, feature_code = 'PPL', admin1 = 'X') =>
    ({name, population, feature_code, admin1, country_code: 'US', latitude: 1, longitude: 2, timezone: 'America/New_York'});
  const cities = w.parseCities(JSON.stringify({results: [
    place('Newark', 281944), place('Sacramento', 500000), place('New York', 8804190, 'PPLA', 'New York'),
    place('New York Peak', null, 'MT'), place('Newt', undefined, 'PPL', null)]}), 'New');
  assert.equal(cities.map(c => c.name).join('|'), 'New York|Newark|Newt');
  assert.equal(cities[0].place, 'New York, New York, US');
  assert.equal(cities[2].place, 'Newt, US');
  assert.equal(w.parseCities('not json', 'new').length, 0);
  assert.equal(w.parseCities('{}', 'new').length, 0);
});
check('a picked city is the default only after it is saved', () => {
  let saved = '';
  const weather = {latitude: 0, longitude: 0, timezone: 'America/Chicago', place: '', defaultKey: '',
    userChoice: false, get locationKey() { return this.latitude + ',' + this.longitude + ',' + this.timezone; }};
  const w = context('WeatherState.qml', weather, {defaultFile: {setText: t => { saved = t; }},
    fetchProc: {running: true}});
  w.selectCity({latitude: 40.7, longitude: -74, timezone: 'America/New_York', place: 'New York, New York, US'});
  assert.equal(weather.userChoice, true);
  assert.equal(weather.defaultKey, '');
  w.saveDefault();
  assert.equal(weather.defaultKey, weather.locationKey);
  assert.deepEqual(JSON.parse(saved), {latitude: 40.7, longitude: -74, timezone: 'America/New_York', place: 'New York, New York, US'});
  w.selectCity({latitude: 'bad', longitude: 0});
  assert.equal(weather.place, 'New York, New York, US');
});
check('media position ticks only when a timeline is visible', () => {
  const source = fs.readFileSync(path.join(qs, 'MediaState.qml'), 'utf8');
  const expression = source.match(/readonly property bool timelineShown:([\s\S]*?)\n\n/)[1];
  for (const activeTab of ['overview', 'media', 'system', 'weather']) {
    const dashboard = {panelVisible: true, activeTab};
    assert.equal(vm.runInNewContext(expression, {root: {panelVisible: false}, DashboardState: dashboard}),
      activeTab === 'overview' || activeTab === 'media');
    dashboard.panelVisible = false;
    assert.equal(vm.runInNewContext(expression, {root: {panelVisible: false}, DashboardState: dashboard}), false);
    assert.equal(vm.runInNewContext(expression, {root: {panelVisible: true}, DashboardState: dashboard}), true);
  }
});
check('dashboard toggles per screen and resets to Overview', () => {
  const state = {panelVisible: false, panelScreen: '', activeTab: 'media',
    tabs: ['overview', 'media', 'system', 'weather']};
  const d = context('DashboardState.qml', state);
  d.togglePanel('DP-1');
  assert.equal(state.panelVisible, true);
  assert.equal(state.activeTab, 'overview');
  d.stepTab(1);
  assert.equal(state.activeTab, 'media');
  d.togglePanel('DP-2');
  assert.equal(state.panelScreen, 'DP-2');
  assert.equal(state.activeTab, 'overview');
  d.togglePanel('DP-2');
  assert.equal(state.panelVisible, false);
  d.togglePanel('');
  assert.equal(state.panelVisible, false);
});
check('calendar ISO weeks and leap days stay correct at year boundaries', () => {
  const d = context('DashOverview.qml', {});
  assert.equal(d.isoWeek(new Date(2021, 0, 1)), 53);
  assert.equal(d.isoWeek(new Date(2021, 0, 4)), 1);
  assert.equal(d.dayOfYear(new Date(2024, 11, 31)), 366);
});
if (checks.length) process.exitCode = 1;
