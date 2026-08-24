import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
  id: window
  required property var output
  screen: output

  visible: VideoDownloadState.visible
        && VideoDownloadState.screenName === output.name
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}

  WlrLayershell.namespace: "hyprland-desktop-video-download"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  VideoDownloadCard {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Theme.fs(67)
  }
}
