import Quickshell
import "notifications" as Notifications

Scope {
  // Instantiate battery monitoring even when no bar battery widget is present.
  readonly property var batteryState: BatteryState

  Bar {}
  Variants {
    model: Quickshell.screens

    DesktopClock {
      required property var modelData
      output: modelData
    }
  }
  // Spotify-only now-playing card on every monitor's desktop, hidden while
  // Spotify is closed or has nothing loaded.
  Variants {
    model: Quickshell.screens

    DesktopNowPlaying {
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
