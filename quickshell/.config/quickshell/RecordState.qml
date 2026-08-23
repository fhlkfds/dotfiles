pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Screen-recording state for the bar indicator.
//
// The recorder is owned by capture/record.sh, which keeps its pid in
// $XDG_RUNTIME_DIR. This polls that script's `status` subcommand rather than
// reading the pidfile directly, so the liveness check (validating the pid
// against /proc, clearing stale entries) lives in exactly one place.
//
// Polling rather than a subscription because the recorder is started by a
// keybind, not by a daemon that could stream events; the same Timer+Process
// shape as NetworkState's connectivity check.
Singleton {
  id: root

  readonly property string script: "/home/liam/.config/hypr/scripts/capture/capture.sh"

  property bool recording: false

  // Verified by rasterising against JetBrainsMono Nerd Font: this codepoint is
  // the "REC" badge. The neighbouring MDI names are wrong in this font --
  // 0xf044c, nominally md-record_rec, renders as a recycling symbol.
  readonly property string glyphRecord: String.fromCodePoint(0xf044b)

  function stop() { stopProc.running = true }

  Process {
    id: stopProc
    command: [root.script, "record", "stop"]
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: statusProc.running = true
  }

  Process {
    id: statusProc
    command: [root.script, "record", "status"]
    stdout: StdioCollector {
      onTextChanged: {
        if (text === "")
          return
        root.recording = text.trim() === "recording"
      }
    }
    stderr: StdioCollector {}
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: statusProc.running = true
  }
}
