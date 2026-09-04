import Quickshell
import Quickshell.Wayland
import QtQuick

// Persistent, click-through clock above the wallpaper and below application windows.
PanelWindow {
  id: panel
  required property var output
  screen: output

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}
  WlrLayershell.namespace: "quickshell-desktop-clock"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  Row {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: Theme.fs(56)
    anchors.bottomMargin: Theme.fs(56)
    spacing: Theme.fs(18)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: Qt.formatDateTime(ClockState.zonedDate(), "h:mm")
      color: Theme.text
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(82)
      font.bold: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: ClockState.formats[ClockState.formatIndex].indexOf("AP") !== -1
      text: Qt.formatDateTime(ClockState.zonedDate(), "AP")
      color: Theme.textDim
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(16)
      font.bold: true
    }

    Rectangle {
      width: Theme.fs(3)
      height: Theme.fs(84)
      anchors.verticalCenter: parent.verticalCenter
      color: Theme.textMuted
      opacity: 0.8
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.fs(2)

      Text {
        text: Qt.formatDateTime(ClockState.zonedDate(), "MMMM").toUpperCase()
        color: Theme.text
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(18)
        font.bold: true
      }
      Text {
        text: Qt.formatDateTime(ClockState.zonedDate(), "dd")
        color: Theme.text
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(32)
        font.bold: true
      }
      Text {
        text: Qt.formatDateTime(ClockState.zonedDate(), "dddd")
        color: Theme.textDim
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(16)
        font.bold: true
      }
    }
  }
}
