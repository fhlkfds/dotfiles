//@ pragma UseQApplication
// Tray menus (SystemTrayWidget) are platform menus, which Quickshell can only
// open when it runs as a QApplication. Pragmas must come first in the file.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import "notifications" as Notifications

Scope {
  // Instantiate battery monitoring even when no bar battery widget is present.
  readonly property var batteryState: BatteryState
  // Likewise for Bluetooth device low-battery alerts.
  readonly property var bluetoothState: BluetoothState
  readonly property var osdState: OsdState

  Bar {}
  // Desktop widgets hide under a visible scratchpad (DesktopCover.js), which
  // Hyprland reports only in the monitor IPC object. Refresh it on the event.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activespecial") Hyprland.refreshMonitors()
    }
  }
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
  // Volume and brightness pill. OsdState only shows it on the focused screen.
  Variants {
    model: Quickshell.screens

    OsdPopup {
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
