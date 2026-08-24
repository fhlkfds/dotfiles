import Quickshell
import QtQuick
import "notifications" as Notifications

// Headless parse/instantiation harness used by the validation instructions in
// README.md. It deliberately omits layer-shell window construction.
Scope {
  readonly property var service: Notifications.NotificationService
  property Component borderType: Component { Notifications.NotificationBorder {} }
  property Component cardType: Component { Notifications.NotificationCard {} }
  property Component stackType: Component {
    Notifications.NotificationStack { ownerScreen: "smoke" }
  }
  Timer {
    interval: 250
    running: true
    onTriggered: Qt.quit()
  }
}
