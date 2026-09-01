import Quickshell
import QtQuick

// Headless parse/instantiation harness. The state safely stays off when the
// optional windows package is not Stowed in the fixture environment.
Scope {
  readonly property var state: WindowsVmState
  WindowsVmIcon {}
  Timer {
    interval: 300
    running: true
    onTriggered: Qt.quit()
  }
}
