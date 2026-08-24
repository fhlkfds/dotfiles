import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."

PanelWindow {
  id: window
  required property var output
  screen: output

  readonly property bool atTop: NotificationConfig.position.indexOf("top-") === 0
  readonly property bool atRight: NotificationConfig.position.indexOf("-right") > 0

  visible: true
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "hyprland-desktop-notifications"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  mask: Region { item: stack.inputItem }

  NotificationStack {
    id: stack
    ownerScreen: window.output.name
    anchors.top: window.atTop ? parent.top : undefined
    anchors.bottom: window.atTop ? undefined : parent.bottom
    anchors.left: window.atRight ? undefined : parent.left
    anchors.right: window.atRight ? parent.right : undefined
    anchors.topMargin: window.atTop ? Theme.barHeight + Theme.gapM : 0
    anchors.bottomMargin: window.atTop ? 0 : Theme.gapM
    anchors.leftMargin: window.atRight ? 0 : Theme.gapM
    anchors.rightMargin: window.atRight ? Theme.gapM : 0
  }
}
