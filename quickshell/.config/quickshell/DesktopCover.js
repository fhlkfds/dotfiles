// Background-layer surfaces sit under every window, so a workspace with any
// window on it hides them. Desktop widgets use this to pause or hide.
function covered(monitor) {
  return !!monitor
    && monitor.activeWorkspace !== null
    && monitor.activeWorkspace.toplevels !== null
    && monitor.activeWorkspace.toplevels.values.length > 0
}
