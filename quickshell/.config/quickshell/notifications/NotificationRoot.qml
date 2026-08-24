import Quickshell
import QtQuick

Scope {
  // Force singleton construction before the per-screen views so the D-Bus
  // server and persistence restoration are ready as early as possible.
  readonly property var service: NotificationService

  Variants {
    model: Quickshell.screens
    NotificationOverlay {
      required property var modelData
      output: modelData
    }
  }
}
