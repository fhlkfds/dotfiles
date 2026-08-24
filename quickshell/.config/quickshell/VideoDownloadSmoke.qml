import Quickshell
import QtQuick

// Headless parse/instantiation harness. The layer-shell window is deliberately
// omitted so validation does not need a live compositor.
Scope {
  readonly property var state: VideoDownloadState
  VideoDownloadCard {}
  Timer {
    interval: 250
    running: true
    onTriggered: Qt.quit()
  }
}
