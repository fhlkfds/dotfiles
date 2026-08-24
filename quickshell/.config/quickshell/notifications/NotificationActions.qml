import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
  id: root

  readonly property string helper: Quickshell.env("HOME") + "/.local/bin/notificationctl"
  property var focusQueue: []

  signal focusFailed(string app)

  function focus(entry) {
    root.focusQueue = root.focusQueue.concat([entry])
    root.runNext()
  }

  function runNext() {
    if (focusProc.running || root.focusQueue.length === 0)
      return
    const entry = root.focusQueue[0]
    root.focusQueue = root.focusQueue.slice(1)
    focusProc.appName = String(entry.app || "")
    focusProc.pendingInput = JSON.stringify({
      app: entry.app || "",
      desktopEntry: entry.desktopEntry || "",
      appIcon: entry.appIcon || ""
    })
    focusProc.command = [root.helper, "_focus"]
    focusProc.running = true
  }

  property Process focusProc: Process {
    id: focusProc
    property string appName: ""
    property string pendingInput: ""
    running: false
    stdinEnabled: true
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onStarted: focusProc.write(pendingInput + "\n")
    onExited: function(code) {
      if (code !== 0) root.focusFailed(appName)
      root.runNext()
    }
  }
}
