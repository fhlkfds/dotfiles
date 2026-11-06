import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "DesktopCover.js" as DesktopCover

// Synced lyrics in the middle of the desktop, above the wallpaper and below
// application windows. The empty mask lets every click through to the desktop.
// Hidden while windows cover the workspace, so a translucent terminal does not
// show lyrics behind it.
PanelWindow {
  id: panel
  required property var output
  screen: output

  visible: view.shown
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  mask: view.clickMask
  WlrLayershell.namespace: "quickshell-desktop-lyrics"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  DesktopLyricsContent {
    id: view
    anchors.centerIn: parent
    maxTextWidth: panel.width * 0.6
    covered: DesktopCover.covered(Hyprland.monitorFor(panel.output), Hyprland.workspaces.values)
  }
}
