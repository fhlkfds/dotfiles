import Quickshell
import QtQuick

// Offscreen harness for the configured app launcher: it loads
// app-launcher.json, then routes clicks against a fake compositor and tray.
// Left click focuses the app's window (whatever the class's case) or
// launches it; right click opens the hidden tray item's menu.
Scope {
  id: smoke
  property int failures: 0
  property bool ran: false
  property var launched: []

  QtObject {
    id: compositor
    property var toplevels: ({ values: [] })
    property var requests: []
    function dispatch(request) { requests = requests.concat([request]) }
  }
  QtObject {
    id: spotifyTray
    property string title: "spotify"
    property string icon: "image://icon/spotify-linux-32"
    property bool hasMenu: true
    property var menuAt: null
    function display(parentWindow, x, y) { menuAt = { parentWindow: parentWindow, x: x, y: y } }
  }
  QtObject { id: barWindow }

  AppLauncher {
    id: launcher
    hyprland: compositor
    parentWindow: barWindow
    trayItems: [spotifyTray]
    launch: function(app) { smoke.launched = smoke.launched.concat([app.desktopId]) }
  }

  function check(name, condition) {
    console.log((condition ? "ok   " : "FAIL: ") + name)
    if (!condition) failures += 1
  }

  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (launcher.apps.length === 0 || smoke.ran)
        return
      smoke.ran = true
      const app = launcher.apps[0]
      if (app.desktopId === "spotify" && app.name === "Spotify"
          && app.icon === "spotify-client" && app.wmClass === "spotify")
        console.log("ok: App launcher configuration")
      else
        console.log("FAIL: App launcher configuration")
      const slot = launcher.children.filter(c => c.app !== undefined)[0]

      check("not running: left click launches", launcher.click(app, Qt.LeftButton, slot) === "launch"
            && smoke.launched.join() === "spotify" && compositor.requests.length === 0)

      // Spotify on workspace 9; its class is "Spotify", the config "spotify".
      compositor.toplevels = { values: [
        { address: "56462b14ec10", wayland: { appId: "kitty" } },
        { address: "56462b273980", wayland: { appId: "Spotify" } },
      ] }
      smoke.launched = []
      check("running: left click focuses its window in-process",
            launcher.click(app, Qt.LeftButton, slot) === "focus"
            && compositor.requests.join() === 'hl.dsp.focus({ window = "address:0x56462b273980" })'
            && smoke.launched.length === 0)

      check("right click opens the Spotify tray menu on the bar window",
            launcher.click(app, Qt.RightButton, slot) === "menu"
            && spotifyTray.menuAt !== null && spotifyTray.menuAt.parentWindow === barWindow)

      launcher.trayItems = []
      spotifyTray.menuAt = null
      check("right click without a tray item does nothing",
            launcher.click(app, Qt.RightButton, slot) === "none" && spotifyTray.menuAt === null)

      if (smoke.failures === 0) console.log("ok: App launcher clicks")
      Qt.quit()
    }
  }

  Timer {
    interval: 3000
    running: true
    onTriggered: {
      console.log("FAIL: App launcher smoke test timed out")
      Qt.quit()
    }
  }
}
