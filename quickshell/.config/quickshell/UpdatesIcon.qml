import Quickshell
import QtQuick

Item {
  id: root

  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }

  // A notification, not a permanent fixture: a clean check that finds nothing
  // shows nothing. A failed check is not a clean zero, so it stays visible
  // (muted) with the failure in the hover; otherwise a missing checkupdates or
  // an AUR rate limit would look exactly like an up-to-date system.
  visible: UpdatesState.totalCount > 0 || UpdatesState.updating || UpdatesState.stale

  implicitWidth: label.implicitWidth + root.s(16)
  implicitHeight: label.implicitHeight + root.s(6)

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusCell
    color: UpdatesState.totalCount > 0 && !UpdatesState.stale ? Theme.accent : "transparent"
  }

  Text {
    id: label
    anchors.centerIn: parent
    // An ellipsis while the upgrade terminal is open makes a second click
    // obviously unnecessary, instead of looking like the first one was ignored.
    text: UpdatesState.updating
      ? "󰚰  …"
      : UpdatesState.totalCount === 0 && UpdatesState.stale
        ? "󰚰  !"
        : "󰚰  " + UpdatesState.totalCount
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(14)
    color: UpdatesState.totalCount > 0 && !UpdatesState.stale ? Theme.onAccent : Theme.textMuted
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onClicked: UpdatesState.update()
  }

  PopupWindow {
    visible: root.visible && mouse.containsMouse
    anchor.item: root
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6
    implicitWidth: 360
    implicitHeight: tip.implicitHeight + 16

    Rectangle {
      anchors.fill: parent
      color: Theme.bg
    }

    Text {
      id: tip
      anchors.centerIn: parent
      width: parent.width - 20
      horizontalAlignment: Text.AlignLeft
      wrapMode: Text.Wrap
      text: "Pacman (" + UpdatesState.repoCount + "): "
            + (UpdatesState.repoPackages.length > 0
              ? UpdatesState.repoPackages.join(", ")
              : "None")
            + "\nAUR (" + UpdatesState.aurCount + "): "
            + (UpdatesState.aurPackages.length > 0
              ? UpdatesState.aurPackages.join(", ")
              : "None")
            + (UpdatesState.stale ? "\nLast check failed" : "")
            + (UpdatesState.updating
              ? "\nUpdating…"
              : UpdatesState.updateQueued
                ? "\nUpdate queued until the check finishes"
                : "\nClick to update")
      color: Theme.text
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(12)
    }
  }
}
