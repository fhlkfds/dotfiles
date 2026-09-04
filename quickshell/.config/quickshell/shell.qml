import Quickshell
import "notifications" as Notifications

Scope {
  Bar {}
  Variants {
    model: Quickshell.screens

    DesktopClock {
      required property var modelData
      output: modelData
    }
  }
  Notifications.NotificationRoot {}
  VideoDownloadRoot {}
}
