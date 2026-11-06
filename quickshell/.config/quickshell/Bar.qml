import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Scope {
  id: bar
  property bool barVisible: true

  // Panels opened from a keybind rather than a click target the focused
  // monitor, so they land where the user is looking.
  function focusedScreen(): string {
    const f = Hyprland.focusedMonitor
    return f ? f.name : ""
  }
  IpcHandler {
    target: "bar"
    function toggle(): string {
      bar.barVisible = !bar.barVisible
      return JSON.stringify({visible: bar.barVisible})
    }
    function statusJson(): string {
      return JSON.stringify({visible: bar.barVisible})
    }
  }

  IpcHandler {
    target: "network"
    function toggle(): void {
      NetworkState.togglePanel(bar.focusedScreen())
    }
    function manage(): void {
      NetworkState.togglePanel(bar.focusedScreen())
    }
    function speedTest(): void {
      NetworkState.runSpeedTest(bar.focusedScreen())
    }
    // The lmenu "Share Wi-Fi as a QR code" rows: opens WifiQrOverlay on the
    // focused monitor without going through the network panel.
    function shareWifi(): void {
      NetworkState.showWifiQr(bar.focusedScreen())
    }
  }

  IpcHandler {
    target: "disk"
    function speedTest(): void {
      DiskState.open(bar.focusedScreen())
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
    target: "dashboard"
    function toggle(): void {
      DashboardState.togglePanel(bar.focusedScreen())
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
    // screensaver-lock keeps these entries when it wipes history on lock.
    function pinnedData(): string {
      return ClipboardState.pinnedData()
    }
  }

  // The clipboard QR is an overlay rather than a bar panel, so it has no
  // toggle target of its own on the bar: the lmenu Capture row calls this.
  IpcHandler {
    target: "clipboard-qr"
    function toggle(): void {
      ClipboardQrState.show(bar.focusedScreen())
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
    target: "app-keybinds"
    function neovim(): void {
      AppKeybindsState.togglePanel(bar.focusedScreen(), "neovim")
    }
    function herdr(): void {
      AppKeybindsState.togglePanel(bar.focusedScreen(), "herdr")
    }
  }

  IpcHandler {
    target: "theme"
    function toggle(): void {
      ThemeState.togglePanel(bar.focusedScreen())
    }
    // Called by the generator after it installs themes/.active/theme.json.
    // Needed because that install is an atomic rename, which kills the file
    // watcher in Theme.qml -- see the comment there.
    function reload(): void {
      Theme.reloadPalette()
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
    // Super+Space, via ~/.local/bin/webapp-current. Takes no argument: the
    // script leaves the URL in $XDG_RUNTIME_DIR/webapp-current-url and
    // WebAppState reads it from there. See the handoff comment in
    // WebAppState.qml.
    function installCurrent(): void {
      WebAppState.installCurrent(bar.focusedScreen())
    }
  }

  // Pokes from scripts whose state the bar would otherwise have to poll fast:
  // capture/record.sh on start/stop and windows-vm on start/stop.
  IpcHandler {
    target: "record"
    function refresh(): void {
      RecordState.refresh()
    }
  }

  IpcHandler {
    target: "windows-vm"
    function refresh(): void {
      WindowsVmState.refresh()
    }
  }

  IpcHandler {
    target: "modes"
    function toggle(): void {
      ModesState.togglePanel(bar.focusedScreen())
    }
  }

  // Super+Shift+N and the lmenu "Night light schedule…" row.
  IpcHandler {
    target: "nightlight"
    function toggle(): void {
      NightLightState.togglePanel(bar.focusedScreen())
    }
  }

  // lmenu opens from a Hyprland global shortcut (hl.dsp.global("quickshell:lmenu")
  // in keybindings.lua) rather than `quickshell ipc call`, so the keypress
  // reaches the shell without starting a process. The IPC target is for scripts
  // that want to open it at a route: `quickshell ipc call lmenu summon themes`.
  GlobalShortcut {
    name: "lmenu"
    description: "lmenu root"
    onPressed: LmenuState.toggle(bar.focusedScreen(), "")
  }

  // Panel keys from keybindings.lua's shell() helper, for the same reason.
  CloseWindowShortcut {}
  GlobalShortcut { name: "keybinds"; description: "keybindings palette"; onPressed: KeybindsState.togglePanel(bar.focusedScreen()) }
  GlobalShortcut { name: "neovim-keybinds"; description: "Neovim keybindings"; onPressed: AppKeybindsState.togglePanel(bar.focusedScreen(), "neovim") }
  GlobalShortcut { name: "herdr-keybinds"; description: "Herdr keybindings"; onPressed: AppKeybindsState.togglePanel(bar.focusedScreen(), "herdr") }
  GlobalShortcut { name: "clipboard"; description: "clipboard history"; onPressed: ClipboardState.togglePanel(bar.focusedScreen()) }
  GlobalShortcut { name: "visualizer"; description: "audio visualizer"; onPressed: VisualizerState.toggle() }
  GlobalShortcut { name: "network"; description: "network panel"; onPressed: NetworkState.togglePanel(bar.focusedScreen()) }
  GlobalShortcut { name: "network-speedtest"; description: "network speed test"; onPressed: NetworkState.runSpeedTest(bar.focusedScreen()) }
  GlobalShortcut { name: "display"; description: "display panel"; onPressed: DisplayState.togglePanel(bar.focusedScreen()) }
  GlobalShortcut { name: "media"; description: "media panel"; onPressed: MediaState.togglePanel(bar.focusedScreen()) }
  GlobalShortcut { name: "audio"; description: "audio panel"; onPressed: AudioState.togglePanel(bar.focusedScreen()) }
  GlobalShortcut { name: "bluetooth"; description: "Bluetooth panel"; onPressed: BluetoothState.togglePanel(bar.focusedScreen()) }
  GlobalShortcut { name: "theme"; description: "theme picker"; onPressed: ThemeState.togglePanel(bar.focusedScreen()) }
  GlobalShortcut { name: "nightlight"; description: "night light schedule"; onPressed: NightLightState.togglePanel(bar.focusedScreen()) }
  GlobalShortcut { name: "webapps"; description: "web app manager"; onPressed: WebAppState.togglePanel(bar.focusedScreen()) }

  IpcHandler {
    target: "lmenu"
    function toggle(route: string): void {
      LmenuState.toggle(bar.focusedScreen(), route)
    }
    function summon(route: string): void {
      LmenuState.summon(bar.focusedScreen(), route)
    }
    function close(): void {
      LmenuState.close()
    }
  }

  Variants {
    model: Quickshell.screens

    LmenuPanel {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
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

  Variants {
    model: Quickshell.screens

    KeybindsPanel {
      required property var modelData
      screen: modelData
      ownerScreen: modelData.name
      controller: AppKeybindsState
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

    NightLightPanel {
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

    SpeedTestOverlay {
      required property var modelData
      output: modelData
    }
  }

  Variants {
    model: Quickshell.screens

    DiskSpeedOverlay {
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
      visible: bar.barVisible

      // The bar is pinned to the top edge; there is no way to move it.
      anchors {
        top: true
        left: true
        right: true
      }
      implicitHeight: Theme.barHeight

      // Content scale for the bar: the tallest chrome is the workspace cell at
      // 26 design px, so 1.25x gives 33px inside a 40px island -- about 3px of
      // padding above and below. Narrow bars scale down instead, so the three
      // island groups keep their separation on a rotated monitor. See
      // Theme.barScaleFor for why the curve is what it is.
      readonly property real barScale: Theme.barScaleFor(width)

      // The strip paints nothing of its own. Everything visible is a BarIsland
      // floating on it, which is what makes the bar read as capsules over the
      // wallpaper instead of as a slab across the top of the screen.
      color: "transparent"

      // The whole reserved strip still swallows clicks, gaps between islands
      // included, so a drag that overshoots an island edge cannot land on
      // whatever sits behind the bar.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }

      BarIsland {
        id: leftIsland
        anchors.left: parent.left
        anchors.leftMargin: Theme.barSideMargin
        anchors.verticalCenter: parent.verticalCenter
        moduleSpacing: Theme.fs(4 * panel.barScale)

        WorkspacesModule { id: workspaces; barScale: panel.barScale }
      }

      // The clock is the center anchor. Indicators grow left without nudging
      // it, and a glance widens the capsule around it. See BarCenter.qml.
      BarCenter {
        id: centerGroup
        anchors.fill: parent
        barScale: panel.barScale
        screenName: panel.modelData.name
        leftEdge: leftIsland.x + leftIsland.width
        rightEdge: rightGroup.x
        // The time and the weather beside it open the dashboard.
        onClockClicked: DashboardState.togglePanel(panel.modelData.name)

        RecordIcon { barScale: panel.barScale }
        UpdatesIcon { barScale: panel.barScale }
        ModeIndicators { screenName: panel.modelData.name; barScale: panel.barScale }
      }

      DashboardPanel {
        anchorItem: centerGroup.clock
        ownerScreen: panel.modelData.name
      }

      // The media panel anchors to the centered clock and opens through the
      // `media` IPC target or the expanded island's now-playing row.
      MediaPanel {
        anchorItem: centerGroup.clock
        ownerScreen: panel.modelData.name
      }

      IslandPanel {
        anchorItem: centerGroup.capsule
        ownerScreen: panel.modelData.name
      }

      Row {
        id: rightGroup
        anchors.right: parent.right
        anchors.rightMargin: Theme.barSideMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.barIslandGap

        BarIsland {
          id: trayIsland
          anchors.verticalCenter: parent.verticalCenter
          moduleSpacing: Theme.fs(2 * panel.barScale)

          // Using SystemTray here is what makes the shell the desktop's tray
          // host. Without it, apps find no tray and hide their icons.
          // Pinned apps draw in AppLauncher, so the tray skips their icons.
          SystemTrayWidget { parentWindow: panel; barScale: panel.barScale; pinnedApps: appLauncher.apps }
          AppLauncher { id: appLauncher; parentWindow: panel; barScale: panel.barScale }
          WindowsVmIcon { barScale: panel.barScale }
          BluetoothIcon { screenName: panel.modelData.name; barScale: panel.barScale }
          NetworkIcon { screenName: panel.modelData.name; barScale: panel.barScale }
          AudioIcon { screenName: panel.modelData.name; barScale: panel.barScale }
          BatteryIcon { barScale: panel.barScale }
        }

        // Power gets a circular island of its own. It is the only destructive
        // control on the bar, so it does not share a capsule with the icons a
        // mis-aimed click would otherwise be one pixel away from.
        BarIsland {
          id: powerIsland
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: Theme.barIslandHeight

          IconButton {
            id: powerButton
            anchors.verticalCenter: parent.verticalCenter
            bordered: false
            glyph: String.fromCodePoint(0xf0425) // md-power
            size: Theme.fs(28 * panel.barScale)
            glyphSize: Theme.fs(15 * panel.barScale)
            onClicked: powerPopup.visible = !powerPopup.visible
          }
        }
      }

      PowerPopup {
        id: powerPopup
        anchorItem: powerButton
      }

      // Keep the clipboard and display panels available through their IPC
      // shortcuts after removing their bar icons.
      ClipboardPanel {
        anchorItem: trayIsland
        ownerScreen: panel.modelData.name
      }

      DisplayPanel {
        anchorItem: trayIsland
        ownerScreen: panel.modelData.name
      }
    }
  }
}
