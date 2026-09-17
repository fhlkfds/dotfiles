import QtQuick

// The connected-device card at the top of BluetoothPanel.
//
// Deliberately quiet: a plain surface with an accent stripe down its left
// edge rather than an accent-tinted block, because the panel's palette is
// theme-swapped and a saturated accent filling the panel's first element
// reads as an alert in half of them. The whole card disconnects; the
// "Disconnect" label is the affordance, not a separate target.
Rectangle {
  id: root

  property string address: ""
  property string name: ""
  property string icon: ""
  property int battery: -1

  readonly property var device: ({
    address: root.address, name: root.name, paired: true,
    connected: true, trusted: false, icon: root.icon, battery: root.battery
  })

  readonly property string pending: BluetoothState.pendingFor(root.address)
  readonly property bool busy: root.pending !== ""
  readonly property bool failed: BluetoothState.lastError !== ""
                             && BluetoothState.errorAddress === root.address

  height: Theme.fs(62)
  radius: Theme.radiusRow
  color: cardArea.containsMouse ? Theme.surface : Theme.bgDeep
  border.width: Theme.borderWidth
  border.color: root.failed ? Theme.error : "transparent"

  Behavior on color {
    ColorAnimation { duration: Theme.animFast }
  }

  // The accent stripe. Clipped to the card's own radius by matching it on the
  // left corners and letting the card's fill cover the right half.
  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Theme.fs(3)
    radius: parent.radius
    color: Theme.accent
  }

  MouseArea {
    id: cardArea
    anchors.fill: parent
    hoverEnabled: true
    enabled: !root.busy
    onClicked: BluetoothState.disconnectDevice(root.device)
  }

  Text {
    id: heroGlyph
    anchors.left: parent.left
    anchors.leftMargin: Theme.gapL
    anchors.verticalCenter: parent.verticalCenter
    text: BluetoothState.glyphForDevice(root.device)
    font.family: Theme.glyphFamily
    font.pixelSize: Theme.fs(26)
    color: Theme.accent
  }

  Column {
    anchors.left: heroGlyph.right
    anchors.leftMargin: Theme.gapM
    anchors.right: disconnectLabel.left
    anchors.rightMargin: Theme.gapS
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.fs(3)

    Text {
      width: parent.width
      text: root.name
      color: Theme.text
      font.pixelSize: Theme.fs(14)
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: root.failed || root.busy
      text: root.failed ? BluetoothState.lastError
          : BluetoothState.actionLabel(root.pending) + "…"
      color: root.failed ? Theme.error : Theme.warning
      font.pixelSize: Theme.fs(10)
      font.bold: true
      elide: Text.ElideRight
    }

    BluetoothBattery {
      visible: !root.failed && !root.busy
      level: root.battery
    }
  }

  Text {
    id: disconnectLabel
    anchors.right: parent.right
    anchors.rightMargin: Theme.gapL
    anchors.verticalCenter: parent.verticalCenter
    text: "Disconnect"
    color: cardArea.containsMouse ? Theme.text : Theme.textMuted
    font.pixelSize: Theme.fs(10)
    font.bold: true
    opacity: root.busy ? Theme.opacityDisabled : 1
  }
}
