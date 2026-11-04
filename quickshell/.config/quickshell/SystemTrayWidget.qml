import QtQuick
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import "tray/TrayAppsLogic.js" as TrayApps

// Tray icons (StatusNotifierItem) for apps such as Hermes Chat or nm-applet.
// Using SystemTray at all is what makes the shell the desktop's tray host, so
// this module must stay on the bar or every app loses its tray icon.
//
// One icon per app: an app pinned in AppLauncher draws there instead (its
// icon opens this item's menu), and duplicate items draw once. Left click
// jumps to the app's window, switching workspace, without spawning anything.
Row {
  id: root
  required property var parentWindow
  property real barScale: 1.0
  // The smoke swaps in fake items, apps and compositor; the bar uses the
  // real tray and Hyprland.
  property var items: SystemTray.items
  property var pinnedApps: []
  property var hyprland: Hyprland
  // Read `.values` here, in the binding, so it re-runs as items come and go.
  // (A plain array, as the smoke passes, has a .values() method of its own.)
  readonly property var shownItems: TrayApps.visibleItems(
    Array.isArray(root.items) ? root.items : (root.items ? root.items.values : []), root.pinnedApps)
  function s(n) { return Theme.fs(n * root.barScale) }
  spacing: root.s(2)

  // One place for click routing, so the smoke can test it without a pointer.
  // Left click focuses the app's window when it has one. Right click, or a
  // click on a menu-only item with no window, opens the menu under the icon.
  // `display` takes window coordinates, not the icon's own.
  function click(item, button, anchor) {
    if (button === Qt.MiddleButton) {
      item.secondaryActivate()
      return "secondary"
    }
    if (button === Qt.LeftButton) {
      const target = TrayApps.windowFor(item, TrayApps.windowsFrom(root.hyprland.toplevels))
      const request = target ? TrayApps.focusRequest(target.address) : ""
      if (request !== "") {
        root.hyprland.dispatch(request)
        return "focus"
      }
    }
    if ((button === Qt.RightButton || item.onlyMenu) && item.hasMenu) {
      const p = anchor.mapToItem(null, 0, anchor.height)
      item.display(root.parentWindow, Math.round(p.x), Math.round(p.y))
      return "menu"
    }
    if (button === Qt.LeftButton) {
      item.activate()
      return "activate"
    }
    return "none"
  }

  Repeater {
    model: root.shownItems

    Item {
      id: slot
      required property var modelData
      implicitWidth: root.s(26)
      implicitHeight: root.s(26)

      // `icon` is already an image URL (theme name, file or pixmap). Passing
      // it through Quickshell.iconPath again breaks every themed icon.
      Image {
        anchors.centerIn: parent
        width: root.s(16)
        height: root.s(16)
        sourceSize.width: width
        sourceSize.height: height
        source: slot.modelData.icon
        fillMode: Image.PreserveAspectFit
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => root.click(slot.modelData, mouse.button, slot)
        onWheel: wheel => slot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }
  }
}
