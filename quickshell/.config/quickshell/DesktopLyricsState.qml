pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// On/off switch for the desktop lyrics, saved so it survives a restart. The
// lmenu entry flips it over IPC and reads the same file for its checkmark.
Singleton {
  id: root

  readonly property string stateFilePath: {
    const configured = Quickshell.env("XDG_STATE_HOME")
    return (configured ? configured : Quickshell.env("HOME") + "/.local/state")
      + "/hyprland-desktop/desktop-lyrics.json"
  }
  readonly property bool enabled: saved.enabled

  function toggle() {
    saved.enabled = !saved.enabled
  }

  FileView {
    id: stateFile
    path: root.stateFilePath
    atomicWrites: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    onLoadFailed: function (error) {
      if (error === FileViewError.FileNotFound)
        stateFile.writeAdapter()
    }

    JsonAdapter {
      id: saved
      property bool enabled: true
    }
  }

  IpcHandler {
    target: "lyrics"
    function toggle(): string {
      root.toggle()
      return JSON.stringify({ enabled: root.enabled })
    }
  }
}
