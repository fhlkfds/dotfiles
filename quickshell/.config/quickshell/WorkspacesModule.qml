import QtQuick
import Quickshell.Hyprland
import "workspaces/WorkspacesLogic.js" as WorkspacesLogic

Row {
  id: root

  // Bar chrome scale, passed down from Bar.qml. Kept separate from Theme.fs so
  // the bar can be sized independently of the panels and of GTK text scaling.
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }
  spacing: root.s(4)

  property var workspaceList: Hyprland.workspaces ? Hyprland.workspaces.values : []
  property var focusedWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : null
  readonly property var ids: WorkspacesLogic.visibleIds(root.workspaceList, root.focusedWorkspaceId)
  property alias cellRepeater: cells

  Repeater {
    id: cells
    model: root.ids

    Rectangle {
      id: cell
      width: root.s(26)
      height: root.s(26)
      radius: root.s(5)
      readonly property bool isFocused: root.focusedWorkspaceId === modelData
      // Theme roles rather than fixed colours, so the badges read on light
      // themes as well as dark ones.
      readonly property color textColor: isFocused ? Theme.onAccent : Theme.text
      color: isFocused ? Theme.accent : "transparent"

      // The workspace number. Ids above 9 are two digits and still fit the cell.
      Text {
        anchors.centerIn: parent
        text: String(modelData)
        font.family: Theme.uiFamily
        font.pixelSize: root.s(14)
        font.bold: true
        color: cell.textColor
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        // Hyprland 0.55+ evaluates dispatches as Lua expressions. Quickshell
        // wraps this in hl.dispatch(...), so the expression must be an
        // hl.dsp dispatcher rather than the old "workspace N" text command.
        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + modelData + "\" })")
      }
    }
  }
}
