import QtQuick
import Quickshell

PopupWindow {
  id: popup
  required property Item anchorItem

  visible: false
  grabFocus: true

  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: 6

  // Matches the previous nesting, which added 20px twice around the grid.
  implicitWidth: grid.implicitWidth + 40
  implicitHeight: grid.implicitHeight + 40

  Rectangle {
    anchors.fill: parent
    color: Theme.bg
  }

  Item {
    id: content
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: popup.visible = false

    CalendarGrid {
      id: grid
      anchors.centerIn: parent
    }
  }

  onVisibleChanged: if (visible) content.forceActiveFocus()
}
