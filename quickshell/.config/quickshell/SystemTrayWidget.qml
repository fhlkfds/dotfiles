import QtQuick
import Quickshell.Services.SystemTray

// Tray icons (StatusNotifierItem) for apps such as Hermes Chat or nm-applet.
// Using SystemTray at all is what makes the shell the desktop's tray host, so
// this module must stay on the bar or every app loses its tray icon.
Row {
  id: root
  required property var parentWindow
  property real barScale: 1.0
  // The smoke swaps in fake items; the bar always uses the real tray.
  property var items: SystemTray.items
  function s(n) { return Theme.fs(n * root.barScale) }
  spacing: root.s(2)

  // One place for click routing, so the smoke can test it without a pointer.
  // Right click, or any click on a menu-only item, opens the menu under the
  // icon. `display` takes window coordinates, not the icon's own.
  function click(item, button, anchor) {
    if (button === Qt.MiddleButton) {
      item.secondaryActivate()
      return "secondary"
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
    model: root.items

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
