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

  implicitWidth: content.implicitWidth + 20
  implicitHeight: content.implicitHeight + 20

  // Short, easily-editable list. First entry resets to system time.
  readonly property var zones: [
    { id: "", label: "Local (America/Chicago)" },
    { id: "America/New_York", label: "America/New_York" },
    { id: "America/Denver", label: "America/Denver" },
    { id: "America/Los_Angeles", label: "America/Los_Angeles" },
    { id: "UTC", label: "UTC" }
  ]

  Rectangle {
    anchors.fill: parent
    color: Theme.bg
  }

  Item {
    id: content
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: popup.visible = false

    implicitWidth: layout.implicitWidth + 20
    implicitHeight: layout.implicitHeight + 20

    Column {
      id: layout
      anchors.centerIn: parent
      spacing: Theme.fs(2)

      Repeater {
        model: popup.zones
        Rectangle {
          width: Theme.fs(180)
          height: Theme.fs(26)
          radius: Theme.fs(4)
          property bool hovered: false
          color: hovered ? Theme.surface : "transparent"

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.fs(8)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            color: Theme.text
            font.pixelSize: Theme.fs(12)
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: parent.hovered = true
            onExited: parent.hovered = false
            onClicked: {
              ClockState.tzId = modelData.id
              popup.visible = false
            }
          }
        }
      }
    }
  }

  onVisibleChanged: if (visible) content.forceActiveFocus()
}
