import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

// Spotify now-playing card above the wallpaper and below application windows,
// one per output, in the bottom-left corner opposite the desktop clock.
//
// Unlike DesktopClock this window is sized to the card rather than the whole
// screen, so the buttons take clicks while the rest of the desktop stays
// untouched, and the record's animation repaints a small surface.
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

  visible: SpotifyState.hasTrack
  anchors { bottom: true; left: true }
  margins { bottom: Theme.fs(56); left: Theme.fs(56) }
  implicitWidth: card.implicitWidth + Theme.fs(8)
  implicitHeight: card.implicitHeight + Theme.fs(8)
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "quickshell-desktop-now-playing"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  DesktopNowPlayingCard {
    id: card
    anchors.centerIn: parent
    spinAllowed: !panel.covered
  }
}
