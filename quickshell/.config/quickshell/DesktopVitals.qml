import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

// System vitals card above the wallpaper and below application windows, one per
// output, in the top-right corner under the bar.
//
// Sized to the card like DesktopNowPlaying, so the rest of the desktop keeps
// its clicks. `covered` is read by shell.qml, which only lets SysState poll
// while at least one card can actually be seen.
PanelWindow {
  id: panel
  required property var output
  screen: output

  readonly property var monitor: Hyprland.monitorFor(output)
  // Background-layer surfaces are hidden by any window on the workspace.
  readonly property bool covered: monitor !== null
    && monitor.activeWorkspace !== null
    && monitor.activeWorkspace.toplevels !== null
    && monitor.activeWorkspace.toplevels.values.length > 0

  // Ignoring exclusive zones means the bar's strip is not subtracted, so the
  // top margin has to clear it explicitly.
  anchors { top: true; right: true }
  margins { top: Theme.barHeight + Theme.fs(24); right: card.edgeMargin }
  implicitWidth: card.implicitWidth
  implicitHeight: card.implicitHeight
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}
  WlrLayershell.namespace: "quickshell-desktop-vitals"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  DesktopVitalsCard {
    id: card
    anchors.fill: parent
  }
}
