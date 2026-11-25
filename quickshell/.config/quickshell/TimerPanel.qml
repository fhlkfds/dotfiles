import QtQuick
import Quickshell
import Quickshell.Wayland

// Timer panel (SUPER+ALT+Z, the bar pill, or lmenu). One instance per monitor,
// only the one matching panelScreen visible, same layer-shell shape as
// ModesPanel. The click-catching layer is clear: a timer picker should not
// dim the screen. Escape, a click outside, the key again and SUPER+Q all close.
PanelWindow {
  id: panel
  required property string ownerScreen

  visible: TimerState.panelVisible && TimerState.panelScreen === ownerScreen
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "quickshell-timer"

  MouseArea { anchors.fill: parent; onClicked: TimerState.close() }

  Rectangle {
    anchors.top: parent.top
    anchors.topMargin: Theme.barHeight + Theme.gapS
    anchors.horizontalCenter: parent.horizontalCenter
    width: content.width + 2 * Theme.gapL
    height: content.height + 2 * Theme.gapL
    radius: Theme.menuRadius
    color: Theme.bg
    border.width: Theme.menuBorderWidth
    border.color: Theme.borderActive1
    MouseArea { anchors.fill: parent }

    TimerPanelContent {
      id: content
      x: Theme.gapL
      y: Theme.gapL
      width: implicitWidth
      height: implicitHeight
      onCloseRequested: TimerState.close()
    }
  }
}
