pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Do Not Disturb state, owned by swaync.
//
// swaync is the notification daemon on this session -- started by systemd via
// graphical-session.target, not by autostart.conf -- and it is the single
// source of truth for DND. This singleton mirrors that state and never keeps a
// copy of its own beyond what the last event said.
//
// scripts/dnd.sh is the shared backend: the same script the Super+Ctrl+,
// keybind runs. The bar and the keybind therefore cannot drift apart.
Singleton {
  id: root

  // The one place the helper path lives.
  readonly property string script: "/home/liam/.config/hypr/scripts/dnd.sh"

  property bool dnd: false
  property int count: 0

  // Verified by rasterising the codepoint against JetBrainsMono Nerd Font --
  // the neighbouring "bell" names in the MDI range are not the bell glyphs.
  readonly property string glyphBellOff: String.fromCodePoint(0xf0a91) // md-bell_off_outline

  function toggle() { toggleProc.running = true }
  function openHistory() { historyProc.running = true }

  Process { id: toggleProc;  command: [root.script, "toggle"] }
  Process { id: historyProc; command: [root.script, "history"] }

  // swaync emits one JSON line per notification event, and one immediately on
  // connect -- so the icon is primed at startup and updated on change with no
  // polling and no timer.
  //
  //   { "count": 0, "dnd": false, "visible": false, "inhibited": false }
  Process {
    id: subProc
    running: true
    command: [root.script, "subscribe"]

    stdout: SplitParser {
      onRead: function (line) {
        if (!line)
          return
        try {
          const ev = JSON.parse(line)
          if (ev.dnd !== undefined)
            root.dnd = ev.dnd
          if (ev.count !== undefined)
            root.count = ev.count
        } catch (e) {
          // A partial or non-JSON line is not worth tearing the bar down over.
        }
      }
    }
    stderr: StdioCollector {}

    // swaync restarting (config reload, crash) drops the stream. Reconnect so
    // the indicator cannot silently freeze on a stale value.
    onExited: reconnect.start()
  }

  Timer {
    id: reconnect
    interval: 2000
    repeat: false
    onTriggered: subProc.running = true
  }
}
