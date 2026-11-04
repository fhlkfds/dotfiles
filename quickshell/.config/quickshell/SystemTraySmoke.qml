import QtQuick
import Quickshell

// Headless check of the tray module against stand-in tray items and a fake
// compositor (no session bus, tray apps or Hyprland needed): one icon per app,
// icon URLs used as given, and which clicks focus a window, open the menu,
// activate, or do nothing.
FloatingWindow {
  id: window
  implicitWidth: 400
  implicitHeight: 80

  // Records what the module asked a tray item to do.
  component FakeItem: QtObject {
    property string title: ""
    property string icon: ""
    property bool hasMenu: true
    property bool onlyMenu: false
    property var calls: []
    property var menuAt: null
    function activate() { calls = calls.concat("activate") }
    function secondaryActivate() { calls = calls.concat("secondary") }
    function display(parentWindow, x, y) {
      calls = calls.concat("menu")
      menuAt = { parentWindow: parentWindow, x: x, y: y }
    }
    function scroll(delta, horizontal) { calls = calls.concat("scroll") }
  }

  FakeItem { id: themed; title: "NetworkManager Applet"; icon: "image://icon/nm-no-connection" }
  FakeItem { id: menuOnly; title: "hermes-chat"; icon: "image://icon/hermes-chat"; onlyMenu: true }
  FakeItem { id: noMenu; title: "plain"; icon: "image://icon/plain"; hasMenu: false }
  // Pinned in the launcher, so the tray must not draw it a second time.
  FakeItem { id: spotify; title: "spotify"; icon: "image://icon/spotify-linux-32" }
  // The same app registering twice draws once.
  FakeItem { id: plainAgain; title: "plain"; icon: "image://icon/plain" }

  // Hyprland stand-in: windows as the live session reports them (no 0x).
  QtObject {
    id: compositor
    property var toplevels: ({ values: [] })
    property var requests: []
    function dispatch(request) { requests = requests.concat([request]) }
  }

  SystemTrayWidget {
    id: tray
    // Off the window's origin, so window and icon coordinates differ.
    x: 40
    y: 10
    parentWindow: window
    hyprland: compositor
    items: [themed, spotify, menuOnly, noMenu, plainAgain]
    pinnedApps: [{ desktopId: "spotify", name: "Spotify", icon: "spotify-client", wmClass: "spotify" }]
  }

  Component.onCompleted: {
    let failures = 0
    function check(label, ok) {
      if (ok) console.log("ok   " + label)
      else { failures++; console.log("FAIL " + label) }
    }
    function reset() {
      for (const item of [themed, menuOnly, noMenu, spotify]) { item.calls = []; item.menuAt = null }
      compositor.requests = []
    }
    const slots = tray.children.filter(c => c.modelData !== undefined)
    const iconOf = slot => slot.children[0].source.toString()

    check("one icon per app: pinned Spotify and the duplicate are not drawn",
          slots.length === 3 && slots[0].modelData === themed && slots[1].modelData === menuOnly
          && slots[2].modelData === noMenu)
    check("icon URL is used as given: " + iconOf(slots[0]),
          iconOf(slots[0]) === "image://icon/nm-no-connection")

    reset()
    check("right click opens the menu", tray.click(themed, Qt.RightButton, slots[0]) === "menu"
          && themed.calls.join() === "menu")
    const below = slots[0].mapToItem(null, 0, slots[0].height)
    check("menu opens on the bar window", themed.menuAt.parentWindow === window)
    check("menu opens under the icon, in window coordinates: "
          + themed.menuAt.x + "," + themed.menuAt.y,
          themed.menuAt.x === Math.round(below.x) && themed.menuAt.y === Math.round(below.y)
          && themed.menuAt.x >= 40 && themed.menuAt.y > 10)

    reset()
    check("left click activates", tray.click(themed, Qt.LeftButton, slots[0]) === "activate"
          && themed.calls.join() === "activate")
    check("middle click is the secondary action",
          tray.click(themed, Qt.MiddleButton, slots[0]) === "secondary"
          && themed.calls.join() === "activate,secondary")

    reset()
    check("left click on a menu-only item with no window opens its menu",
          tray.click(menuOnly, Qt.LeftButton, slots[1]) === "menu" && menuOnly.calls.join() === "menu")

    // Hermes Chat open on another workspace: left click jumps to it.
    compositor.toplevels = { values: [
      { address: "56462b273980", wayland: { appId: "Spotify" } },
      { address: "56462b3205c0", wayland: { appId: "hermes-chat" } },
    ] }
    reset()
    check("left click focuses the app's window by address",
          tray.click(menuOnly, Qt.LeftButton, slots[1]) === "focus"
          && compositor.requests.join() === 'hl.dsp.focus({ window = "address:0x56462b3205c0" })'
          && menuOnly.calls.length === 0)
    reset()
    check("right click still opens the menu when the app has a window",
          tray.click(menuOnly, Qt.RightButton, slots[1]) === "menu" && compositor.requests.length === 0)
    reset()
    check("left click on an app with no window keeps its own action",
          tray.click(themed, Qt.LeftButton, slots[0]) === "activate" && compositor.requests.length === 0)

    reset()
    check("right click without a menu does nothing",
          tray.click(noMenu, Qt.RightButton, slots[2]) === "none" && noMenu.calls.length === 0)

    if (failures === 0) console.log("ok: system tray smoke")
    else console.log("system tray smoke: " + failures + " failed")
    exitTimer.start()
  }

  // Quitting from onCompleted has no receivers yet; defer past start-up.
  Timer { id: exitTimer; interval: 50; onTriggered: Qt.quit() }
}
