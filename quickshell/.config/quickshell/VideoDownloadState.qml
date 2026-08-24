pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  property bool visible: false
  property int percent: 0
  property string screenName: ""

  function focusedScreenName() {
    const monitor = Hyprland.focusedMonitor
    if (monitor && monitor.name) return monitor.name
    return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
  }

  function update(value) {
    const parsed = Number(value)
    if (!isFinite(parsed)) return "invalid"
    if (!root.visible) root.screenName = root.focusedScreenName()
    root.percent = Math.max(0, Math.min(100, Math.round(parsed)))
    root.visible = root.screenName !== ""
    hideTimer.restart()
    return root.visible ? "ok" : "no-screen"
  }

  function hide() {
    root.visible = false
    hideTimer.stop()
    return "ok"
  }

  Timer {
    id: hideTimer
    interval: 8000
    repeat: false
    onTriggered: root.visible = false
  }

  IpcHandler {
    target: "videoDownload"
    function setProgress(percent: int): string { return root.update(percent) }
    function close(): string { return root.hide() }
    function statusJson(): string {
      return JSON.stringify({visible: root.visible, percent: root.percent,
                             screen: root.screenName})
    }
  }
}
