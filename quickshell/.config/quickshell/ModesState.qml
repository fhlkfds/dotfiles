pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// UI projection of desktop-mode. QML never infers backend state: every icon
// and row is built from the controller's observed JSON status.
Singleton {
  id: root

  readonly property string executable: Quickshell.env("HOME") + "/.local/bin/desktop-mode"
  property bool panelVisible: false
  property string panelScreen: ""
  property var modes: []
  property string lastError: ""
  property bool daemonRunning: false
  property int warmTemperature: 1000
  property int normalTemperature: 6500
  readonly property var defaultPresets: ["30m", "1h", "3h", "8h"]
  property var durationPresets: defaultPresets

  readonly property var metadata: ({
    "night-light": { label: "Night light", glyph: String.fromCodePoint(0xf0594), detail: root.warmTemperature + "K warm display" },
    // badge is optional short text drawn beside the glyph in the bar pill.
    // DND carries one because the bell glyph alone is easy to miss.
    "do-not-disturb": { label: "Do not disturb", glyph: String.fromCodePoint(0xf0a91), badge: "DND", detail: "Hide toasts, preserve history" },
    "stay-awake": { label: "Stay awake", glyph: String.fromCodePoint(0xf0f2e), detail: "No screensaver, screen off, lock or sleep" },
    "screensaver-auto": { label: "Automatic screensaver", glyph: String.fromCodePoint(0xf06a9), detail: "Run after configured inactivity" }
  })

  function mode(name) {
    for (let i = 0; i < modes.length; i++)
      if (modes[i].name === name) return modes[i]
    return { name: name, desired: false, observed: false, available: false,
             expires_at: null, error: "Status unavailable" }
  }

  function togglePanel(screenName) {
    if (screenName === "") return
    if (panelVisible && panelScreen === screenName) {
      panelVisible = false
      return
    }
    panelScreen = screenName
    panelVisible = true
    refresh()
  }

  function close() { panelVisible = false }
  function refresh() { if (!statusProc.running) statusProc.running = true }

  // Emitted when an invoke()d command exits; ok is exit status 0.
  signal actionFinished(bool ok)

  // False when another action is still running and this one did not start.
  function invoke(args) {
    if (actionProc.running) return false
    actionProc.command = [root.executable].concat(args)
    actionProc.running = true
    return true
  }

  function toggle(name) { return invoke(["toggle", name]) }
  function timed(name, duration) { return invoke(["enable", name, "--for", duration]) }
  function screensaver() { invoke(["action", "screensaver"]) }

  // "18:30" for an expires_at in epoch seconds; adds the weekday past today.
  function clockTime(epochSeconds) {
    const end = new Date(epochSeconds * 1000)
    const sameDay = end.toDateString() === new Date().toDateString()
    return Qt.formatDateTime(end, sameDay ? "HH:mm" : "ddd HH:mm")
  }

  function applyStatus(text) {
    if (text.trim() === "") return
    try {
      const value = JSON.parse(text)
      root.modes = value.modes || []
      root.daemonRunning = value.daemon === true
      const settings = value.settings || ({})
      root.warmTemperature = settings.warm_temperature || 1000
      root.normalTemperature = settings.normal_temperature || 6500
      root.durationPresets = settings.duration_presets || root.defaultPresets
      root.lastError = ""
    } catch (error) {
      root.lastError = "Invalid desktop-mode status: " + error
    }
  }

  // One-shot status for immediate feedback after an action or panel open.
  Process {
    id: statusProc
    command: [root.executable, "status", "--json"]
    stdout: StdioCollector { onTextChanged: root.applyStatus(text) }
    stderr: StdioCollector {}
    onExited: (code, status) => {
      if (code !== 0) root.lastError = "desktop-mode status is unavailable"
    }
  }

  Process {
    id: actionProc
    command: [root.executable, "status"]
    stdout: StdioCollector {}
    stderr: StdioCollector {
      onTextChanged: if (text.trim() !== "") root.lastError = text.trim()
    }
    onExited: (code, status) => {
      if (code === 0) root.lastError = ""
      refreshDelay.restart()
      root.actionFinished(code === 0)
    }
  }

  Timer {
    id: refreshDelay
    interval: 150
    onTriggered: root.refresh()
  }

  // Background updates come from one resident `desktop-mode watch`, which
  // prints a status line only when something changed. Polling `status` every
  // two seconds started a bash wrapper and a fresh Python interpreter each time.
  Process {
    id: watchProc
    command: [root.executable, "watch"]
    running: true
    stdout: SplitParser { onRead: line => root.applyStatus(line) }
    stderr: StdioCollector {}
    onExited: (code, status) => {
      root.lastError = "desktop-mode status is unavailable"
      watchRestart.restart()
    }
  }

  Timer {
    id: watchRestart
    interval: 5000
    onTriggered: watchProc.running = true
  }
}
