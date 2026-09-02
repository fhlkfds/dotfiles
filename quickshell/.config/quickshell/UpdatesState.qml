pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/arch-updates"
  property int repoCount: 0
  property int aurCount: 0
  property int totalCount: 0
  property bool updating: false

  function refresh() {
    if (!countProc.running && !updateProc.running)
      countProc.running = true
  }

  function update() {
    if (!updateProc.running) {
      root.updating = true
      updateProc.running = true
    }
  }

  Process {
    id: countProc
    command: [root.script, "count"]
    stdout: StdioCollector { id: countOutput }
    stderr: StdioCollector {}
    onExited: function(code) {
      if (code !== 0)
        return
      try {
        const result = JSON.parse(countOutput.text.trim())
        root.repoCount = Math.max(0, Number(result.repo) || 0)
        root.aurCount = Math.max(0, Number(result.aur) || 0)
        root.totalCount = root.repoCount + root.aurCount
      } catch (error) {
        console.warn("UpdatesState: invalid count output:", error)
      }
    }
  }

  Process {
    id: updateProc
    command: [root.script, "update"]
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: function() {
      root.updating = false
      root.refresh()
    }
  }

  Timer {
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
