import Quickshell
import QtQuick

Scope {
  readonly property var state: UpdatesState
  UpdatesIcon {}
  Timer {
    interval: 3000
    running: true
    onTriggered: Qt.quit()
  }
}
