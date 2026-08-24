import QtQuick

Item {
  id: root

  property real barScale: 1.0
  function s(n) { return Theme.fs(n * root.barScale) }
  required property string screenName

  implicitWidth: label.implicitWidth + root.s(16)
  implicitHeight: label.implicitHeight + root.s(6)

  Text {
    id: label
    anchors.centerIn: parent
    text: BluetoothState.glyph
    font.family: Theme.glyphFamily
    font.pixelSize: root.s(15)
    color: BluetoothState.connectedCount > 0 ? Theme.accent
         : BluetoothState.powered ? Theme.text : Theme.textMuted
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: BluetoothState.togglePanel(root.screenName)
  }

  BluetoothPanel {
    anchorItem: root
    ownerScreen: root.screenName
  }
}
