.pragma library

// Reduces the caption daemon's NDJSON events to what the pill shows. A state
// event is the whole state, so there is nothing to merge: a line either
// replaces the state or is ignored. A level event only moves the mic meter of
// the current listening session. Pure and clockless; the daemon owns every
// deadline.

var PHASES = { idle: true, armed: true, listening: true, typing: true }

var HINTS = {
  loading: "Loading speech model…",
  "no-audio": "No microphone audio",
  "engine-failed": "Live captions unavailable"
}
var PLACEHOLDER = "Listening…"

function initialState() {
  return { phase: "idle", id: "", seq: -1, committed: "", tentative: "", note: "", level: 0 }
}

function text(value) {
  return typeof value === "string" ? value : ""
}

function receive(state, line) {
  var event
  try {
    event = JSON.parse(line)
  } catch (error) {
    return state
  }
  if (event === null || typeof event !== "object") return state
  if (event.type === "level") return receiveLevel(state, event)
  if (event.type !== "state") return state
  if (typeof event.seq !== "number" || !isFinite(event.seq) || event.seq <= state.seq) return state
  if (typeof event.phase !== "string" || !PHASES.hasOwnProperty(event.phase)) return state
  var id = text(event.id)
  return {
    phase: event.phase,
    id: id,
    seq: event.seq,
    committed: text(event.committed),
    tentative: text(event.tentative),
    note: text(event.note),
    level: event.phase === "listening" && id === state.id ? state.level : 0
  }
}

function receiveLevel(state, event) {
  if (state.phase !== "listening" || event.id !== state.id) return state
  if (typeof event.level !== "number" || !isFinite(event.level)) return state
  var level = Math.max(0, Math.min(1, event.level))
  if (level === state.level) return state
  var next = {}
  for (var key in state) next[key] = state[key]
  next.level = level
  return next
}

// A new connection restarts the daemon's view of us, and its seq may restart.
function disconnected(state) {
  return initialState()
}

function isSpace(ch) {
  return ch === " " || ch === "\n" || ch === "\t"
}

function display(state, maxChars) {
  var committed = state.committed
  var tentative = state.tentative
  var gap = committed !== "" && tentative !== "" && !isSpace(committed.charAt(committed.length - 1)) && !isSpace(tentative.charAt(0)) ? " " : ""
  var full = committed + gap + tentative
  var limit = Math.max(1, maxChars | 0)
  var start = 0
  if (full.length > limit) {
    start = full.length - limit
    if (!isSpace(full.charAt(start - 1))) {
      var space = start
      while (space < full.length && !isSpace(full.charAt(space))) space++
      // A single word longer than the limit has no boundary to cut at.
      if (space < full.length - 1) start = space + 1
    }
  }
  var cutAt = committed.length
  var settled = start < cutAt ? committed.slice(start) : ""
  var pending = full.slice(Math.max(start, cutAt + gap.length))
  if (gap !== "" && settled !== "" && pending !== "") settled += gap
  if (start > 0) {
    if (settled !== "") settled = "…" + settled
    else pending = "…" + pending
  }
  var shown = state.phase !== "idle"
  var hint = !shown ? "" : HINTS.hasOwnProperty(state.note) ? HINTS[state.note] : (full === "" ? PLACEHOLDER : "")
  var level = state.phase === "listening" ? state.level : 0
  return { visible: shown, phase: state.phase, settled: settled, pending: pending, hint: hint, level: level }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    initialState: initialState,
    receive: receive,
    disconnected: disconnected,
    display: display
  }
}
