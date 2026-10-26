import Quickshell.Hyprland

// Layer-shell menus are not Hyprland windows: close the menu before dispatching
// a window close, so Super+Q cannot reach the application underneath it.
// Hyprland 0.55+ evaluates dispatches as Lua, so the old "killactive" text
// command is ignored; send the hl.dsp dispatcher instead.
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
      root.hyprland.dispatch("hl.dsp.window.close()")
  }
}
