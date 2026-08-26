import Quickshell
import QtQuick

// Headless parse/instantiation harness for the state and bar projection. The
// layer-shell panel itself is omitted because it requires a live compositor.
Scope {
  readonly property var state: ModesState
  ModeIndicators { screenName: "fixture" }
  // Compile the layer-shell panel without constructing a window; construction
  // is reserved for the live Wayland session.
  Component { ModesPanel { ownerScreen: "fixture" } }
  Timer {
    interval: 300
    running: true
    onTriggered: Qt.quit()
  }
}
