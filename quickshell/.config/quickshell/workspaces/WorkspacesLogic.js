// Which workspaces get a numbered badge in the bar's workspace module. Pure:
// the module passes in Hyprland's workspaces, so the rules run under node and
// in a headless smoke.

function windowCount(ws) {
  return ws && ws.toplevels && ws.toplevels.values ? ws.toplevels.values.length : 0
}

// Ascending workspace ids to draw: every workspace holding a window, on any
// monitor, plus the focused one. Special (scratchpad) workspaces have negative
// ids and are skipped. Before a focus is known (startup, no IPC) only the
// occupied workspaces show.
function visibleIds(workspaces, focusedId) {
  const shown = {}
  const list = workspaces || []
  for (let i = 0; i < list.length; i++)
    if (list[i] && list[i].id > 0 && windowCount(list[i]) > 0) shown[list[i].id] = true
  if (focusedId !== null && focusedId !== undefined && focusedId > 0) shown[focusedId] = true
  return Object.keys(shown).map(Number).sort((a, b) => a - b)
}

if (typeof module !== "undefined" && module) {
  module.exports = { visibleIds: visibleIds }
}
