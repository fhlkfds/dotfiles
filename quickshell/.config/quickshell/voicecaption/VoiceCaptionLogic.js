.pragma library

// Reduces the caption daemon's NDJSON events to what the pill shows: whether
// dictation is on, a hint when live words cannot work, and the mic level. The
// words are typed into the text box by the daemon, so their text in a state
// event is ignored here. A state event is the whole state, so there is nothing
// to merge: a line either replaces the state or is ignored. A level event only
// moves the mic meter of the current listening session. Pure and clockless;
// the daemon owns every deadline.

var PHASES = { idle: true, armed: true, listening: true, typing: true }

var HINTS = {
  loading: "Loading speech model…",
  "no-audio": "No microphone audio",
  "engine-failed": "Live captions unavailable"
}

function initialState() {
  return { phase: "idle", id: "", seq: -1, note: "", level: 0 }
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
  var id = typeof event.id === "string" ? event.id : ""
  return {
    phase: event.phase,
    id: id,
    seq: event.seq,
    note: typeof event.note === "string" ? event.note : "",
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

function display(state) {
  var shown = state.phase !== "idle"
  return {
    visible: shown,
    phase: state.phase,
    hint: shown && HINTS.hasOwnProperty(state.note) ? HINTS[state.note] : "",
    level: state.phase === "listening" ? state.level : 0
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    initialState: initialState,
    receive: receive,
    disconnected: disconnected,
    display: display
  }
}
