import QtQuick

// Bar item: appears only while Do Not Disturb is on, as the reminder that the
// desktop has been silenced deliberately. Clicking it turns DND back off.
//
// Nothing is lost while it is showing -- silenced notifications still go to
// swaync's control center, which Super+Shift+Alt+, opens.
Item {
  id: root

  // Bar chrome scale, passed down from Bar.qml.
  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }

  // A Row skips invisible children, so the bar closes up when DND is off.
  visible: NotifyState.dnd

  implicitWidth: label.implicitWidth + root.s(16)
  implicitHeight: label.implicitHeight + root.s(6)

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusCell
    color: Theme.accent
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: NotifyState.glyphBellOff
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(15)
    color: Theme.bgDeep
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: NotifyState.toggle()
  }
}
