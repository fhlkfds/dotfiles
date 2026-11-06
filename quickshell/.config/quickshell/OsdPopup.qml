import Quickshell
import Quickshell.Wayland
import QtQuick

// Bottom-centre volume and brightness pill on the overlay layer. Every screen
// has one, but only the screen that was focused when the pill appeared shows
// it. The empty mask makes it click-through.
PanelWindow {
  id: window
  required property var output
  screen: output

  visible: OsdState.screenName === output.name && (OsdState.visible || pill.opacity > 0)
  color: "transparent"
  anchors.bottom: true
  margins.bottom: Theme.fs(96)
  implicitWidth: pill.implicitWidth
  implicitHeight: pill.implicitHeight
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}

  WlrLayershell.namespace: "quickshell-osd"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  OsdPill {
    id: pill
    anchors.fill: parent
    osd: OsdState
  }
}
