import QtQuick
import Quickshell

// Headless check of the tray module against stand-in tray items (no session
// bus or tray apps needed): one icon per item, icon URLs used as given, and
// which clicks open the menu, activate, or do nothing.
FloatingWindow {
  id: window
  implicitWidth: 400
  implicitHeight: 80

  // Records what the module asked a tray item to do.
  component FakeItem: QtObject {
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

  FakeItem { id: themed; icon: "image://icon/nm-no-connection" }
  FakeItem { id: menuOnly; icon: "image://icon/hermes-chat"; onlyMenu: true }
  FakeItem { id: noMenu; icon: "image://icon/plain"; hasMenu: false }

  SystemTrayWidget {
    id: tray
    // Off the window's origin, so window and icon coordinates differ.
    x: 40
    y: 10
    parentWindow: window
    items: [themed, menuOnly, noMenu]
  }

  Component.onCompleted: {
    let failures = 0
    function check(label, ok) {
      if (ok) console.log("ok   " + label)
      else { failures++; console.log("FAIL " + label) }
    }
    function reset() { for (const item of [themed, menuOnly, noMenu]) { item.calls = []; item.menuAt = null } }
    const slots = tray.children.filter(c => c.modelData !== undefined)
    const iconOf = slot => slot.children[0].source.toString()

    check("one icon per tray item", slots.length === 3)
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
    check("left click on a menu-only item opens its menu",
          tray.click(menuOnly, Qt.LeftButton, slots[1]) === "menu" && menuOnly.calls.join() === "menu")

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
