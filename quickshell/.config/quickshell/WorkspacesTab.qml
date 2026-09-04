import QtQuick
import Quickshell.Hyprland

Item {
  id: root
  implicitWidth: Theme.perfPageW
  implicitHeight: Theme.perfPageH

  readonly property var workspaces: Hyprland.workspaces ? Hyprland.workspaces.values : []

  Text {
    anchors.centerIn: parent
    visible: root.workspaces.length === 0
    text: "No Hyprland workspaces"
    color: Theme.textMuted
    font.pixelSize: Theme.fs(13)
  }

  Grid {
    anchors.left: parent.left
    anchors.top: parent.top
    columns: 3
    columnSpacing: Theme.gapM
    rowSpacing: Theme.gapM

    Repeater {
      model: root.workspaces

      Card {
        required property var modelData
        readonly property var workspace: modelData
        readonly property int windowCount: workspace.toplevels ? workspace.toplevels.values.length : 0
        readonly property bool occupied: windowCount > 0

        implicitWidth: Theme.fs(270)
        implicitHeight: Theme.fs(92)
        radius: Theme.radiusM
        color: workspace.active ? Theme.accent : Theme.surface

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Theme.gapL
          anchors.verticalCenter: parent.verticalCenter
          text: workspace.name || workspace.id
          color: workspace.active ? Theme.onAccent : Theme.text
          font.bold: true
          font.pixelSize: Theme.fs(26)
        }

        Column {
          anchors.right: parent.right
          anchors.rightMargin: Theme.gapL
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.gapXS

          Text {
            anchors.right: parent.right
            text: workspace.active ? "ACTIVE" : (occupied ? "OCCUPIED" : "EMPTY")
            color: workspace.active ? Theme.onAccent : Theme.textDim
            font.bold: true
            font.pixelSize: Theme.fs(10)
          }
          Text {
            anchors.right: parent.right
            text: windowCount + (windowCount === 1 ? " window" : " windows")
            color: workspace.active ? Theme.onAccent : Theme.textMuted
            font.pixelSize: Theme.fs(11)
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: workspace.activate()
        }
      }
    }
  }
}
