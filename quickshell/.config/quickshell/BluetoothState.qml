pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  property bool panelVisible: false
  property string panelScreen: ""

  property bool available: false
  property bool powered: false
  property bool scanning: false
  property var devices: []
  property string lastError: ""
  property bool actionErrorActive: false
  property bool busy: false
  property string busyAction: ""
  property string pendingAddress: ""

  // Keep the backend below the already-linked Hyprland config tree so adding
  // this widget does not require a separate ~/.local/bin Stow link.
  readonly property string backend: Quickshell.env("HOME")
    + "/.config/hypr/scripts/bluetooth-control"
  readonly property int connectedCount: devices.filter(device => device.connected).length
  readonly property string glyph: {
    if (!available || !powered)
      return String.fromCodePoint(0xf00b2) // md-bluetooth_off
    if (connectedCount > 0)
      return String.fromCodePoint(0xf00b1) // md-bluetooth_connect
    return String.fromCodePoint(0xf00af)   // md-bluetooth
  }

  function togglePanel(screenName) {
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    if (screenName === "")
      return
    panelScreen = screenName
    panelVisible = true
    refresh()
  }

  function refresh() {
    if (!statusProc.running)
      statusProc.running = true
  }

  function runAction(action, argument) {
    if (busy)
      return
    const command = [backend, action]
    if (argument !== undefined && argument !== "")
      command.push(argument)
    busy = true
    busyAction = action
    pendingAddress = (action === "connect" || action === "disconnect" || action === "pair")
      ? argument : ""
    lastError = ""
    actionErrorActive = false
    actionProc.command = command
    actionProc.running = true
  }

  function setPower(enabled) {
    runAction("power", enabled ? "on" : "off")
  }

  function scan() {
    runAction("scan", "12")
  }

  function activateDevice(device) {
    if (!device || !device.address)
      return
    if (device.connected)
      runAction("disconnect", device.address)
    else if (device.paired)
      runAction("connect", device.address)
    else
      runAction("pair", device.address)
  }

  Process {
    id: statusProc
    command: [root.backend, "status"]
    stdout: StdioCollector { id: statusOut }
    stderr: StdioCollector { id: statusErr }

    onExited: function(code) {
      if (code !== 0) {
        root.available = false
        root.powered = false
        root.devices = []
        root.lastError = statusErr.text.trim() || "Could not read Bluetooth status"
        return
      }
      try {
        const state = JSON.parse(statusOut.text)
        root.available = state.available === true
        root.powered = state.powered === true
        root.scanning = state.scanning === true
        root.devices = Array.isArray(state.devices) ? state.devices : []
        if (!root.actionErrorActive)
          root.lastError = state.error || ""
      } catch (error) {
        root.available = false
        root.powered = false
        root.devices = []
        root.lastError = "Bluetooth returned invalid status"
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {}
    stderr: StdioCollector { id: actionErr }

    onExited: function(code) {
      root.busy = false
      root.busyAction = ""
      root.pendingAddress = ""
      root.actionErrorActive = code !== 0
      if (code !== 0)
        root.lastError = actionErr.text.trim() || "Bluetooth action failed"
      root.refresh()
    }
  }

  Timer {
    interval: root.panelVisible ? 2000 : 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
