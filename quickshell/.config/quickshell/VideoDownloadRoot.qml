import Quickshell
import QtQuick

Scope {
  readonly property var state: VideoDownloadState

  Variants {
    model: Quickshell.screens
    VideoDownloadOverlay {
      required property var modelData
      output: modelData
    }
  }
}
