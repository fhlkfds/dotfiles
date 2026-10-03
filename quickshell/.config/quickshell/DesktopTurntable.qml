import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

// The Turntable over the wallpaper and below application windows, one per
// output, filling the screen. It fades in when an allowed player has a track
// and out when it goes idle, leaving the wallpaper as it was.
//
// The window stays mapped while faded out: background-layer surfaces stack in
// the order they map, so mapping only while playing would put the room on top
// of the desktop clock. shell.qml creates it before the clock for the same
// reason. Its empty input mask makes it click-through like the clock; the
// controls live in the media panel.
PanelWindow {
  id: panel
  required property var output
  screen: output

  readonly property var monitor: Hyprland.monitorFor(output)
  // Background-layer surfaces are hidden by any window on the workspace; stop
  // the record spinning there so it does not keep the output redrawing.
  readonly property bool covered: monitor !== null
    && monitor.activeWorkspace !== null
    && monitor.activeWorkspace.toplevels !== null
    && monitor.activeWorkspace.toplevels.values.length > 0

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}
  WlrLayershell.namespace: "quickshell-desktop-turntable"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  DesktopTurntableScene {
    anchors.fill: parent
    spinAllowed: !panel.covered
  }
}
