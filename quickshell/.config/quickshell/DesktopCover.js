// Background-layer surfaces sit under every window, so a workspace with any
// window on it hides them. Desktop widgets use this to pause or hide.
// A visible special (scratchpad) workspace is drawn over the active one but is
// not part of activeWorkspace; Hyprland reports it only in the monitor's IPC
// object, so look it up by name in `workspaces`.
function covered(monitor, workspaces) {
  if (!monitor) return false
  if (hasWindows(monitor.activeWorkspace)) return true
  const ipc = monitor.lastIpcObject
  const special = ipc && ipc.specialWorkspace ? ipc.specialWorkspace.name : ""
  if (!special) return false
  return (workspaces || []).some(w => w && w.name === special && hasWindows(w))
}

function hasWindows(workspace) {
  return !!workspace && !!workspace.toplevels && workspace.toplevels.values.length > 0
}
