// Rules for the centre island's glances. Pure, so they run under node and in
// IslandSmoke.qml. IslandState.qml owns the timer and the event sources.
//
// A glance is {kind, glyph, title, body, screen}, where an empty screen means
// every bar. A queue is {current, pending}:
// one glance on screen and at most one waiting per kind.

var defaultKinds = {
  notification: { holdMs: 5000, priority: 2 },
  media: { holdMs: 3500, priority: 1 }
}

// Config values override defaults per field; anything malformed keeps the
// default, so a typo in config.json never silences a kind.
function kindTable(raw) {
  var source = raw && typeof raw === "object" ? raw : {}
  var table = {}
  for (var kind in defaultKinds) {
    var given = source[kind] && typeof source[kind] === "object" ? source[kind] : {}
    var hold = Number(given.holdMs)
    var priority = Number(given.priority)
    table[kind] = {
      holdMs: isFinite(hold) && hold >= 500 && hold <= 60000
        ? Math.round(hold) : defaultKinds[kind].holdMs,
      priority: isFinite(priority) ? Math.round(priority) : defaultKinds[kind].priority
    }
  }
  return table
}

function emptyQueue() {
  return { current: null, pending: [] }
}

// A newer glance of the same kind replaces the older one, whether it is on
// screen or waiting. Waiting glances run highest priority first, oldest first
// within a priority.
function enqueue(queue, glance, kinds) {
  if (!glance || !kinds[glance.kind]) return queue
  if (!queue.current) return { current: glance, pending: queue.pending }
  if (queue.current.kind === glance.kind) return { current: glance, pending: queue.pending }
  var pending = queue.pending.filter(function(g) { return g.kind !== glance.kind })
  var at = pending.length
  while (at > 0 && kinds[pending[at - 1].kind].priority < kinds[glance.kind].priority) at--
  pending.splice(at, 0, glance)
  return { current: queue.current, pending: pending }
}

function advance(queue) {
  return { current: queue.pending.length ? queue.pending[0] : null, pending: queue.pending.slice(1) }
}

function holdFor(queue, kinds) {
  return queue.current ? kinds[queue.current.kind].holdMs : 0
}

function remember(list, glance, limit) {
  return [glance].concat(list).slice(0, Math.max(0, limit))
}

// The capsule while a glance shows: the resting capsule widened symmetrically
// about the clock's centre, never past minX or maxX (the neighbouring islands).
function capsuleSpan(rest, centre, wanted, minX, maxX) {
  var half = Math.max(0, Math.min(wanted / 2, centre - minX, maxX - centre))
  var left = Math.min(rest.x, centre - half)
  var right = Math.max(rest.x + rest.width, centre + half)
  return { x: left, width: right - left }
}

if (typeof module !== "undefined" && module) {
  module.exports = {
    kindTable: kindTable,
    emptyQueue: emptyQueue,
    enqueue: enqueue,
    advance: advance,
    holdFor: holdFor,
    remember: remember,
    capsuleSpan: capsuleSpan
  }
}
