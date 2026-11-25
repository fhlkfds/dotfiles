.pragma library

// Reduces the caption daemon's NDJSON snapshots to what the pill shows. Every
// event is the whole state, so there is nothing to merge: a line either
// replaces the state or is ignored. Pure and clockless; the daemon owns every
// deadline.

var PHASES = { idle: true, armed: true, listening: true, typing: true }

var HINTS = {
  loading: "Loading speech model…",
  "no-audio": "No microphone audio",
  "engine-failed": "Live captions unavailable"
}
var PLACEHOLDER = "Listening…"

function initialState() {
  return { phase: "idle", id: "", seq: -1, committed: "", tentative: "", note: "" }
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
  if (event === null || typeof event !== "object" || event.type !== "state") return state
  if (typeof event.seq !== "number" || !isFinite(event.seq) || event.seq <= state.seq) return state
  if (typeof event.phase !== "string" || !PHASES.hasOwnProperty(event.phase)) return state
  return {
    phase: event.phase,
    id: text(event.id),
    seq: event.seq,
    committed: text(event.committed),
    tentative: text(event.tentative),
    note: text(event.note)
  }
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
  return { visible: shown, phase: state.phase, settled: settled, pending: pending, hint: hint }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    initialState: initialState,
    receive: receive,
    disconnected: disconnected,
    display: display
  }
}
