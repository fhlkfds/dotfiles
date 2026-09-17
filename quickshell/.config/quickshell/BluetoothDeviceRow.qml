import QtQuick

// A compact device row for the paired and discovery zones of BluetoothPanel.
//
// The whole row is the connect (or pair) button: this panel exists so one
// click reconnects a known device, so the largest target in the row performs
// the action the user came for. Trust and forget are rare and destructive, so
// they stay hidden until the pointer is over the row, and forget asks first by
// swapping this row's content in place rather than opening anything.
Rectangle {
  id: root

  property string address: ""
  property string name: ""
  property bool paired: false
  property bool connected: false
  property bool trusted: false
  property string icon: ""
  property int battery: -1

  // Rebuilt as a plain object so the state helpers, which are written against
  // the poll's device shape, can be reused unchanged.
  readonly property var device: ({
    address: root.address, name: root.name, paired: root.paired,
    connected: root.connected, trusted: root.trusted, icon: root.icon,
    battery: root.battery
  })

  readonly property string pending: BluetoothState.pendingFor(root.address)
  readonly property bool busy: root.pending !== ""
  readonly property bool failed: BluetoothState.lastError !== ""
                             && BluetoothState.errorAddress === root.address
  property bool confirmingForget: false

  height: Theme.fs(50)
  radius: Theme.radiusRow
  color: rowArea.containsMouse && !root.confirmingForget ? Theme.surface : Theme.bgDeep
  border.width: Theme.borderWidth
  border.color: root.failed ? Theme.error : "transparent"

  Behavior on color {
    ColorAnimation { duration: Theme.animFast }
  }

  function forget() {
    root.confirmingForget = false
    BluetoothState.forgetDevice(root.device)
  }

  MouseArea {
    id: rowArea
    anchors.fill: parent
    hoverEnabled: true
    enabled: BluetoothState.powered && !root.busy && !root.confirmingForget
    onClicked: BluetoothState.activateDevice(root.device)
    onExited: root.confirmingForget = false
  }

  // --- confirmation ----------------------------------------------------------

  Row {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Theme.gapM
    anchors.rightMargin: Theme.gapM
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.gapS
    visible: root.confirmingForget

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - cancelButton.width - forgetButton.width
           - parent.spacing * 2
      text: "Forget " + root.name + "?"
      color: Theme.text
      font.pixelSize: Theme.fs(11)
      elide: Text.ElideRight
    }

    Rectangle {
      id: cancelButton
      anchors.verticalCenter: parent.verticalCenter
      width: Theme.fs(62)
      height: Theme.fs(26)
      radius: Theme.radiusCell
      color: cancelArea.containsMouse ? Theme.surfaceAlt : "transparent"
      border.width: Theme.borderWidth
      border.color: Theme.surfaceAlt

      Text {
        anchors.centerIn: parent
        text: "Cancel"
        color: Theme.text
        font.pixelSize: Theme.fs(10)
        font.bold: true
      }
      MouseArea {
        id: cancelArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.confirmingForget = false
      }
    }

    Rectangle {
      id: forgetButton
      anchors.verticalCenter: parent.verticalCenter
      width: Theme.fs(62)
      height: Theme.fs(26)
      radius: Theme.radiusCell
      color: forgetArea.containsMouse ? Theme.error : "transparent"
      border.width: Theme.borderWidth
      border.color: Theme.error

      Text {
        anchors.centerIn: parent
        text: "Forget"
        color: forgetArea.containsMouse ? Theme.bgDeep : Theme.error
        font.pixelSize: Theme.fs(10)
        font.bold: true
      }
      MouseArea {
        id: forgetArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.forget()
      }
    }
  }

  // An unanswered confirmation reverts itself: a row left mid-question is a
  // row whose click no longer does what it says it does.
  Timer {
    interval: 5000
    running: root.confirmingForget
    onTriggered: root.confirmingForget = false
  }

  // --- normal content --------------------------------------------------------

  Item {
    anchors.fill: parent
    visible: !root.confirmingForget

    Text {
      id: typeGlyph
      anchors.left: parent.left
      anchors.leftMargin: Theme.gapM
      anchors.verticalCenter: parent.verticalCenter
      text: BluetoothState.glyphForDevice(root.device)
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(17)
      color: root.paired ? Theme.textDim : Theme.textMuted
    }

    Column {
      anchors.left: typeGlyph.right
      anchors.leftMargin: Theme.gapM
      anchors.right: actions.left
      anchors.rightMargin: Theme.gapS
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.fs(2)

      Text {
        width: parent.width
        text: root.name
        color: Theme.text
        font.pixelSize: Theme.fs(12)
        font.bold: true
        elide: Text.ElideRight
      }

      // One secondary line, carrying whichever of these matters most right
      // now: a failure, a slow action, the battery, or the hint that a click
      // will connect.
      Item {
        width: parent.width
        height: Theme.fs(13)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          visible: root.failed || root.busy
          text: root.failed ? BluetoothState.lastError
              : BluetoothState.actionLabel(root.pending) + "…"
          color: root.failed ? Theme.error : Theme.warning
          font.pixelSize: Theme.fs(9)
          font.bold: true
          elide: Text.ElideRight
        }

        BluetoothBattery {
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.failed && !root.busy && root.battery >= 0
          level: root.battery
          barColor: Theme.textDim
          textSize: Theme.fs(9)
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.failed && !root.busy && root.battery < 0
          text: rowArea.containsMouse
            ? (root.paired ? "Click to connect" : "Click to pair")
            : (root.paired ? "Paired" : "Available")
          color: Theme.textMuted
          font.pixelSize: Theme.fs(9)
        }
      }
    }

    // Hover-revealed and only for devices BlueZ already knows: neither action
    // means anything for a device that was merely discovered.
    Row {
      id: actions
      anchors.right: parent.right
      anchors.rightMargin: Theme.gapM
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.gapXS
      visible: root.paired && !root.busy
      opacity: rowArea.containsMouse || trustArea.containsMouse
            || forgetHoverArea.containsMouse ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: Theme.animFast }
      }

      IconButton {
        id: trustButton
        anchors.verticalCenter: parent.verticalCenter
        size: Theme.fs(26)
        glyphSize: Theme.fs(12)
        glyph: root.trusted
          ? BluetoothState.glyphTrusted : BluetoothState.glyphUntrusted
        active: root.trusted
        onClicked: BluetoothState.toggleTrust(root.device)

        MouseArea {
          id: trustArea
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
        }
      }

      IconButton {
        id: forgetIcon
        anchors.verticalCenter: parent.verticalCenter
        size: Theme.fs(26)
        glyphSize: Theme.fs(12)
        glyph: BluetoothState.glyphForget
        onClicked: root.confirmingForget = true

        MouseArea {
          id: forgetHoverArea
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
        }
      }
    }
  }
}
