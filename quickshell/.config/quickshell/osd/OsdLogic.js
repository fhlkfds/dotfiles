// One pill slot shared by every kind, so repeated changes update it in place
// instead of stacking. `baseline` holds the last reading per kind; a reading
// from a device not seen before (shell start, a new default sink) only sets
// the baseline, so the pill shows for changes, not for discovery.
var HOLD_MS = 1200

function initialState() {
  return { visible: false, kind: "", level: 0, muted: false, hideAt: 0, baseline: {} }
}

function patched(object, patch) {
  var next = {}
  for (var key in object) next[key] = object[key]
  for (var key2 in patch) next[key2] = patch[key2]
  return next
}

function clampPercent(value) {
  var number = Number(value)
  return isFinite(number) ? Math.max(0, Math.round(number)) : 0
}

// reading: { kind, device, level, muted }. An empty device means the source is
// not ready, which forgets the baseline so its first real reading stays quiet.
function change(state, reading, now) {
  var kind = reading.kind
  var device = String(reading.device || "")
  var level = clampPercent(reading.level)
  var muted = reading.muted === true
  var previous = state.baseline[kind]
  var entry = {}
  entry[kind] = device === "" ? undefined : { device: device, level: level, muted: muted }
  var next = patched(state, { baseline: patched(state.baseline, entry) })

  if (!previous || device === "" || previous.device !== device
      || (previous.level === level && previous.muted === muted))
    return { state: next, shown: false }
  return {
    state: patched(next, { visible: true, kind: kind, level: level, muted: muted, hideAt: now + HOLD_MS }),
    shown: true
  }
}

// A timer armed for an earlier change can fire late; only a deadline that has
// really passed hides the pill.
function expire(state, now) {
  if (!state.visible || now < state.hideAt)
    return state
  return patched(state, { visible: false })
}

function levelText(level, muted) {
  return muted ? "Muted" : clampPercent(level) + "%"
}

if (typeof module !== "undefined") {
  module.exports = {
    HOLD_MS: HOLD_MS,
    initialState: initialState,
    change: change,
    expire: expire,
    levelText: levelText
  }
}
