// Live dictation captions. The daemon publishes whole-state snapshots on a
// unix socket; this singleton only mirrors them. It never spawns a process
// and keeps no hide timer, because the daemon's deadlines decide when idle.
pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import "voicecaption/VoiceCaptionLogic.js" as VoiceCaptionLogic

Singleton {
  id: root

  readonly property string socketPath: Quickshell.env("VOICE_CAPTIONS_EVENTS")
    || (Quickshell.env("XDG_RUNTIME_DIR") + "/voice-captions/events.sock")
  // Two 720-wide lines at the pill's font size hold about this many characters.
  property int maxChars: 150
  readonly property var retryMs: [500, 1000, 2000, 4000, 8000]
  readonly property int retryLongMs: 30000

  property var model: VoiceCaptionLogic.initialState()
  property string screenName: ""
  readonly property var view: VoiceCaptionLogic.display(model, maxChars)
  readonly property bool visible: view.visible
  readonly property string phase: view.phase
  readonly property string settled: view.settled
  readonly property string pending: view.pending
  readonly property string hint: view.hint
  readonly property real level: view.level

  property int attempt: 0

  function focusedScreenName() {
    const monitor = Hyprland.focusedMonitor
    if (monitor && monitor.name) return monitor.name
    return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
  }

  function apply(next) {
    if (next === root.model) return
    if (root.model.phase === "idle" && next.phase !== "idle")
      root.screenName = root.focusedScreenName()
    root.model = next
  }

  function scheduleRetry() {
    if (retryTimer.running) return
    root.apply(VoiceCaptionLogic.disconnected(root.model))
    retryTimer.interval = root.attempt < root.retryMs.length ? root.retryMs[root.attempt] : root.retryLongMs
    ++root.attempt
    retryTimer.start()
  }

  Socket {
    id: socket
    path: root.socketPath
    connected: true
    parser: SplitParser {
      onRead: line => root.apply(VoiceCaptionLogic.receive(root.model, line))
    }
    onConnectedChanged: {
      if (connected) root.attempt = 0
      else root.scheduleRetry()
    }
    onError: root.scheduleRetry()
  }

  Timer {
    id: retryTimer
    repeat: false
    onTriggered: {
      socket.connected = false
      socket.connected = true
    }
  }
}
