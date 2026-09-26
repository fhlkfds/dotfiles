import Quickshell
import QtQuick

// Compiles the real lmenu panel without constructing its layer-shell window.
// PanelWindow needs a Wayland backend even to compile, so
// tests/lmenu-quickshell.test.sh runs this only when a display is available.
Scope {
  Component {
    id: panelFactory
    LmenuPanel { ownerScreen: "smoke" }
  }

  Component.onCompleted: {
    console.log(panelFactory.status === Component.Ready
      ? "ok: lmenu panel compiles"
      : "FAIL: lmenu panel does not compile: " + panelFactory.errorString())
    Qt.quit()
  }
}
