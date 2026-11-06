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
    // With blockLoading, the text() read below waits for this small file, so
    // a saved "off" is known before shell.qml builds the Variants and never
    // creates the widget or loads LyricsState (and its lookups).
    blockLoading: true
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

  Component.onCompleted: stateFile.text()

  IpcHandler {
    target: "lyrics"
    function toggle(): string {
      root.toggle()
      return JSON.stringify({ enabled: root.enabled })
    }
  }
}
