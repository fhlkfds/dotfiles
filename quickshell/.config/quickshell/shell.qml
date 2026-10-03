import Quickshell
import "notifications" as Notifications

Scope {
  // Instantiate battery monitoring even when no bar battery widget is present.
  readonly property var batteryState: BatteryState

  Bar {}
  // The Turntable on every monitor's desktop: the playing album in a room,
  // faded out while no allowed player has a track. Created before the clock,
  // so the clock maps later and stacks above it on the background layer.
  Variants {
    model: Quickshell.screens

    DesktopTurntable {
      required property var modelData
      output: modelData
    }
  }
  Variants {
    model: Quickshell.screens

    DesktopClock {
      required property var modelData
      output: modelData
    }
  }
  Notifications.NotificationRoot {}
  VideoDownloadRoot {}
  // Screen-centred Wi-Fi QR share window: one instance per monitor, only the
  // one whose ownerScreen matches NetworkState.overlayScreen is visible.
  Variants {
    model: Quickshell.screens

    WifiQrOverlay {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
    }
  }
  // The clipboard QR share window, same shape: one instance per monitor, only
  // the one whose ownerScreen matches ClipboardQrState.overlayScreen visible.
  Variants {
    model: Quickshell.screens

    ClipboardQrOverlay {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
    }
  }
}
