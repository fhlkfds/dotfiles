import Quickshell
import QtQuick

// Headless parse/instantiation harness for the hover status tray.
Scope {
  ClockWidget { screenName: "fixture" }
  Timer {
    interval: 300
    running: true
    onTriggered: Qt.quit()
  }
}
