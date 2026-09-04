import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Scope {
  id: bar

  // Panels opened from a keybind rather than a click target the focused
  // monitor, so they land where the user is looking.
  function focusedScreen(): string {
    const f = Hyprland.focusedMonitor
    return f ? f.name : ""
  }

  IpcHandler {
    target: "network"
    function toggle(): void {
      NetworkState.togglePanel(bar.focusedScreen())
    }
    function manage(): void {
      NetworkState.openNmtui()
    }
  }

  IpcHandler {
    target: "audio"
    function toggle(): void {
      AudioState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "bluetooth"
    function toggle(): void {
      BluetoothState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "media"
    function toggle(): void {
      MediaState.togglePanel(bar.focusedScreen())
    }

  }

  IpcHandler {
    target: "visualizer"
    function toggle(): void {
      VisualizerState.toggle()
    }
  }

  IpcHandler {
    target: "clipboard"
    function toggle(): void {
      ClipboardState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "dashboard"
    function toggle(): void {
      DashboardState.togglePanel(bar.focusedScreen())
    }

  }

  IpcHandler {
    target: "display"
    function toggle(): void {
      DisplayState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "keybinds"
    function toggle(): void {
      KeybindsState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "theme"
    function toggle(): void {
      ThemeState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "wallpaper"
    function toggle(): void {
      WallpaperState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "webapps"
    function toggle(): void {
      WebAppState.togglePanel(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "modes"
    function toggle(): void {
      ModesState.togglePanel(bar.focusedScreen())
    }
  }

  // The keybindings palette is a fullscreen overlay rather than a bar-anchored
  // popup, so it gets its own per-screen instance instead of living inside a
  // bar widget. Only the one on the focused monitor ever becomes visible.
  Variants {
    model: Quickshell.screens

    KeybindsPanel {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
    }
  }

  // Same arrangement for the theme gallery: fullscreen, so per-screen instances
  // gated on ThemeState.panelScreen rather than one window that has to move.
  Variants {
    model: Quickshell.screens

    ThemePicker {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
    }
  }

  // The wallpaper gallery deliberately shares the exact theme cover-flow.
  Variants {
    model: Quickshell.screens

    ThemePicker {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
      controller: WallpaperState
      layerNamespace: "quickshell-wallpaper-picker"
    }
  }

  // And the web app manager, same arrangement again.
  Variants {
    model: Quickshell.screens

    WebAppPanel {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
    }
  }

  Variants {
    model: Quickshell.screens

    ModesPanel {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
    }
  }

  Variants {
    model: Quickshell.screens

    CavaEdgeVisualizer {
      required property var modelData
      output: modelData
    }
  }

  Variants {
    model: Quickshell.screens

    CavaEdgeVisualizer {
      required property var modelData
      output: modelData
      anchorTop: true
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData

      anchors {
        top: true
        left: true
        right: true
      }
      implicitHeight: Theme.barHeight

      // Content scale for a 45px bar: the tallest chrome is the workspace cell
      // at 26 design px, so 1.25x gives 33px inside 45px -- about 6px of padding
      // above and below. Capped there rather than filling the bar edge to edge.
      // The width/800 term only bites on a bar narrower than 1000px, where the
      // fixed content (Arch icon, 10 workspace cells, status icons, weekday
      // clock) would otherwise crowd out the centred media widget.
      readonly property real barScale: Math.max(1.0, Math.min(1.25, width / 800))

      Rectangle {
        anchors.fill: parent
        color: Theme.bg
      }

      // Arch button first, then workspaces.
      Row {
        id: leftGroup
        anchors.left: parent.left
        anchors.leftMargin: Theme.fs(8 * panel.barScale)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.fs(6 * panel.barScale)

        ArchIcon { screenName: panel.modelData.name; barScale: panel.barScale }
        WorkspacesModule { id: workspaces; barScale: panel.barScale }
      }

      Item {
        id: barSummary
        anchors.centerIn: parent
        implicitWidth: summary.implicitWidth
        implicitHeight: summary.implicitHeight

        Row {
          id: summary
          spacing: Theme.fs(8 * panel.barScale)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(ClockState.zonedDate(), "ddd, MMM d")
            color: Theme.textDim
            font.family: Theme.uiFamily
            font.pixelSize: Theme.fs(12 * panel.barScale)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(ClockState.zonedDate(), "h:mm AP")
            color: Theme.text
            font.family: Theme.uiFamily
            font.bold: true
            font.pixelSize: Theme.fs(14 * panel.barScale)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: WeatherState.hasData
                  ? WeatherState.codeGlyph(WeatherState.current.code,
                                           WeatherState.current.isDay) : ""
            color: Theme.text
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(15 * panel.barScale)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: WeatherState.hasData
                  ? WeatherState.fmtTemp(WeatherState.current.temp) : "weather…"
            color: Theme.textDim
            font.family: Theme.uiFamily
            font.pixelSize: Theme.fs(12 * panel.barScale)
          }
        }

        // Keep the existing media IPC panel available without showing media
        // metadata in the bar itself.
        MediaPanel {
          anchorItem: barSummary
          ownerScreen: panel.modelData.name
        }
      }

      Row {
        id: rightGroup
        anchors.right: parent.right
        anchors.rightMargin: Theme.fs(8 * panel.barScale)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.fs(2 * panel.barScale)

        // Only rendered while a screen recording is running.
        RecordIcon { barScale: panel.barScale }

        // Amber while Windows is installing/booting, accent when RDP is ready.
        WindowsVmIcon { barScale: panel.barScale }

        // Active temporary modes share one controller and open one focused-
        // monitor panel; notification history remains owned by NotifyState.
        ModeIndicators { screenName: panel.modelData.name; barScale: panel.barScale }

        IconButton {
          anchors.verticalCenter: parent.verticalCenter
          glyph: String.fromCodePoint(0xf0425) // md-power
          size: Theme.fs(28 * panel.barScale)
          glyphSize: Theme.fs(15 * panel.barScale)
          onClicked: powerMenu.running = true
        }

        Process {
          id: powerMenu
          command: ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/power-menu.sh"]
        }
      }
    }
  }
}
