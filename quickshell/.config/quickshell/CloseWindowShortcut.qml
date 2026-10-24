import Quickshell.Hyprland

// Layer-shell menus are not Hyprland windows: close the menu before dispatching
// a window close, so Super+Q cannot reach the application underneath it.
GlobalShortcut {
  id: root
  property var modesState: ModesState
  property var hyprland: Hyprland

  name: "close-window"
  description: "close window"
  onPressed: closeWindow()

  function closeWindow() {
    if (root.modesState.panelVisible)
      root.modesState.close()
    else
      root.hyprland.dispatch(root.hyprland.usingLua ? "hl.dsp.window.close()" : "killactive")
  }
}
