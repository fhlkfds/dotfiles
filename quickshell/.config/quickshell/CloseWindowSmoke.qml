import QtQuick
import Quickshell

Scope {
  id: smoke
  property int failures: 0

  QtObject {
    id: modes
    property bool panelVisible: false
    property int closes: 0
    function close() { panelVisible = false; closes += 1 }
  }
  QtObject {
    id: compositor
    property bool usingLua: true
    property var requests: []
    function dispatch(request) { requests = requests.concat([request]) }
  }
  CloseWindowShortcut {
    id: shortcut
    modesState: modes
    hyprland: compositor
  }

  function check(name, condition) {
    console.log((condition ? "ok   " : "FAIL ") + name)
    if (!condition) failures += 1
  }

  Timer { interval: 1; running: true; onTriggered: smoke.runChecks() }

  function runChecks() {
    modes.panelVisible = true
    shortcut.closeWindow()
    check("Super+Q dismisses desktop modes", !modes.panelVisible && modes.closes === 1)
    check("underlying window stays open", compositor.requests.length === 0)
    shortcut.released()
    check("key release leaves underlying window open", compositor.requests.length === 0)

    shortcut.closeWindow()
    check("Super+Q closes a window when menu is closed",
      compositor.requests.length === 1 && compositor.requests[0] === "hl.dsp.window.close()")
    compositor.usingLua = false
    shortcut.closeWindow()
    check("legacy compositor keeps close-window behavior",
      compositor.requests.length === 2 && compositor.requests[1] === "killactive")
    compositor.requests = []
    modes.panelVisible = true
    shortcut.closeWindow()
    check("legacy compositor also protects the underlying window",
      !modes.panelVisible && compositor.requests.length === 0)
    console.log(failures === 0 ? "ok: close window shortcut" : "FAIL: close window shortcut")
    Qt.quit()
  }
}
