// Pure state machine for the countdown timer. TimerState.qml only holds the
// state, dispatches events, runs the effects and persists.
//
// endsAt is an epoch time, never a time left, so suspend and shell reloads
// cannot drift it. Phases: idle -> running -> done -> idle.
var VERSION = 1
var SECOND_MS = 1000
var MINUTE_MS = 60 * SECOND_MS
var MAX_MS = 24 * 60 * MINUTE_MS
var DEFAULT_PRESETS = [5, 10, 25, 60]
var DEFAULT_SOUND = "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
var MAX_PRESETS = 9

function initialState() {
  return { version: VERSION, phase: "idle", durationMs: 0, endsAt: 0, label: "", notified: false }
}

function patched(state, patch) {
  var next = {}
  for (var key in state) next[key] = state[key]
  for (var key2 in patch) next[key2] = patch[key2]
  return next
}

function cleanLabel(value) {
  return typeof value === "string" ? value.trim().slice(0, 60) : ""
}

function unchanged(state) {
  return { state: state, effects: [] }
}

function changed(state, effects) {
  return { state: state, effects: effects || ["persist"] }
}

// Events: start, addMinute, cancel, tick, dismiss. A no-op returns the same
// state and no effects. Effects come back in the order to run them: persist
// always precedes alert, so a reload during the alert cannot fire it twice.
function reduce(state, event) {
  switch (event.type) {
  case "start": {
    var duration = Number(event.durationMs)
    if (!(duration > 0) || duration > MAX_MS || !isFinite(event.now))
      return unchanged(state)
    return changed({
      version: VERSION, phase: "running", durationMs: duration,
      endsAt: event.now + duration, label: cleanLabel(event.label), notified: false
    })
  }
  case "addMinute":
    if (state.phase !== "running" || state.durationMs + MINUTE_MS > MAX_MS)
      return unchanged(state)
    return changed(patched(state, {
      durationMs: state.durationMs + MINUTE_MS, endsAt: state.endsAt + MINUTE_MS
    }))
  case "cancel":
    return state.phase === "idle" ? unchanged(state) : changed(initialState())
  case "tick":
    if (state.phase !== "running" || !isFinite(event.now) || event.now < state.endsAt)
      return unchanged(state)
    return changed(patched(state, { phase: "done", notified: true }), ["persist", "alert"])
  case "dismiss":
    return state.phase === "done" ? changed(initialState()) : unchanged(state)
  }
  return unchanged(state)
}

// json is the saved file's text. Anything unreadable gives idle. A timer that
// ran out while the shell was down comes back as done, and alerts only if it
// never did.
function restore(json, now) {
  var parsed
  try { parsed = JSON.parse(json) } catch (error) { return unchanged(initialState()) }
  if (!parsed || typeof parsed !== "object" || parsed.version !== VERSION
      || (parsed.phase !== "running" && parsed.phase !== "done"))
    return unchanged(initialState())

  var duration = Number(parsed.durationMs)
  var endsAt = Number(parsed.endsAt)
  if (!isFinite(duration) || duration <= 0 || duration > MAX_MS
      || !isFinite(endsAt) || endsAt <= 0 || endsAt > now + MAX_MS)
    return unchanged(initialState())

  var saved = {
    version: VERSION, phase: parsed.phase, durationMs: duration, endsAt: endsAt,
    label: cleanLabel(parsed.label), notified: parsed.notified === true
  }
  if (saved.phase === "running" && endsAt > now)
    return unchanged(saved)

  if (saved.notified)
    return saved.phase === "done" ? unchanged(saved) : changed(patched(saved, { phase: "done" }))
  return changed(patched(saved, { phase: "done", notified: true }), ["persist", "alert"])
}

function remainingMs(state, now) {
  return state.phase === "running" ? Math.max(0, state.endsAt - now) : 0
}

// Fraction of the timer already used, 0 to 1.
function progress(state, now) {
  if (state.phase !== "running" || !(state.durationMs > 0)) return 0
  return Math.min(1, Math.max(0, 1 - remainingMs(state, now) / state.durationMs))
}

// "7m30s", "1h", "90s", a bare number of minutes, or "7:30". Bare number is
// minutes and the cap is 24 h, the same as parse_duration in desktop_mode.py.
function parseDuration(text) {
  var value = String(text === undefined || text === null ? "" : text).toLowerCase().replace(/\s+/g, "")
  if (value === "") return { error: "type a time, like 7m30s" }

  var seconds
  var clock = /^(\d+):(\d{2})$/.exec(value)
  if (clock) {
    if (Number(clock[2]) > 59) return { error: "seconds go up to 59" }
    seconds = Number(clock[1]) * 60 + Number(clock[2])
  } else {
    if (/^\d+$/.test(value)) value += "m"
    var parts = /^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/.exec(value)
    if (!parts) return { error: "try 90s, 7m30s, 1h or 7:30" }
    seconds = Number(parts[1] || 0) * 3600 + Number(parts[2] || 0) * 60 + Number(parts[3] || 0)
  }
  if (seconds <= 0) return { error: "the time has to be longer than zero" }
  if (seconds * SECOND_MS > MAX_MS) return { error: "24 hours is the longest" }
  return { ms: seconds * SECOND_MS }
}

function pad2(number) {
  return number < 10 ? "0" + number : String(number)
}

// Rounds up to the next whole second so the display never reads 0:00 early.
function formatRemaining(ms) {
  var total = Math.max(0, Math.ceil(ms / SECOND_MS))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor(total % 3600 / 60)
  var seconds = total % 60
  return hours > 0 ? hours + ":" + pad2(minutes) + ":" + pad2(seconds)
                   : minutes + ":" + pad2(seconds)
}

// "7 min 30 s", "1 h 30 min", "45 s".
function describe(ms) {
  var total = Math.max(0, Math.round(ms / SECOND_MS))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor(total % 3600 / 60)
  var seconds = total % 60
  var parts = []
  if (hours > 0) parts.push(hours + " h")
  if (minutes > 0) parts.push(minutes + " min")
  if (seconds > 0) parts.push(seconds + " s")
  return parts.length > 0 ? parts.join(" ") : "0 s"
}

// "15:02:30" in local time.
function clockTime(epochMs) {
  var date = new Date(epochMs)
  return pad2(date.getHours()) + ":" + pad2(date.getMinutes()) + ":" + pad2(date.getSeconds())
}

// Milliseconds until the displayed second next changes, plus a little slack
// so the tick lands just past the boundary. Ticking on the boundary keeps the
// bar readout and the alert on time without a fast poll.
function nextTickDelay(state, now) {
  var left = remainingMs(state, now)
  if (left <= 0) return 16
  return (left - 1) % SECOND_MS + 1 + 2
}

// config.json is user-editable, so bad values fall back instead of throwing.
function normalizeConfig(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var presets = Array.isArray(source.presets) ? source.presets : []
  var valid = presets.length > 0 && presets.length <= MAX_PRESETS
    && presets.every(function (minutes) {
      return typeof minutes === "number" && minutes === Math.round(minutes)
        && minutes > 0 && minutes * MINUTE_MS <= MAX_MS
    })
  return {
    presets: valid ? presets.slice() : DEFAULT_PRESETS.slice(),
    sound: typeof source.sound === "string" && source.sound !== "" ? source.sound : DEFAULT_SOUND
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    VERSION: VERSION, MINUTE_MS: MINUTE_MS, MAX_MS: MAX_MS,
    DEFAULT_PRESETS: DEFAULT_PRESETS, DEFAULT_SOUND: DEFAULT_SOUND,
    initialState: initialState, reduce: reduce, restore: restore,
    remainingMs: remainingMs, progress: progress, parseDuration: parseDuration,
    formatRemaining: formatRemaining, describe: describe, clockTime: clockTime,
    nextTickDelay: nextTickDelay, normalizeConfig: normalizeConfig
  }
}
