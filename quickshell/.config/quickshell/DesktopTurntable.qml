import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

// The Turntable above the wallpaper and below application windows, one per
// output, centred. It fades in when an allowed player has a track and out
// when it goes idle, leaving the wallpaper as it was.
//
// The window is sized to the scene rather than the whole screen so the spinning
// record repaints a smaller surface, and its empty input mask makes it click-
// through like the desktop clock: the controls live in the media panel.
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

  // Stays mapped until the fade-out has finished.
  visible: scene.opacity > 0
  implicitWidth: scene.width + scene.shadowPad * 2
  implicitHeight: scene.height + scene.shadowPad * 2
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}
  WlrLayershell.namespace: "quickshell-desktop-turntable"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  DesktopTurntableScene {
    id: scene
    anchors.centerIn: parent
    unit: unitFor(panel.output.width, panel.output.height)
    spinAllowed: !panel.covered
  }
}
