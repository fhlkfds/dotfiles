import QtQuick
import Quickshell

PopupWindow {
  id: panel
  required property Item anchorItem
  required property string ownerScreen

  visible: BluetoothState.panelVisible
        && BluetoothState.panelScreen === panel.ownerScreen
  grabFocus: true

  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: 6

  implicitWidth: Theme.fs(390)
  implicitHeight: Theme.fs(470)

  Rectangle {
    anchors.fill: parent
    color: Theme.bg

    Item {
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: BluetoothState.panelVisible = false

      Column {
        id: layout
        anchors.fill: parent
        anchors.margins: Theme.fs(16)
        spacing: Theme.fs(12)

        Item {
          width: parent.width
          height: Theme.fs(36)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.fs(10)

            Text {
              text: BluetoothState.glyph
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(22)
              color: BluetoothState.connectedCount > 0 ? Theme.accent : Theme.text
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              spacing: Theme.fs(2)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                text: "Bluetooth"
                color: Theme.text
                font.bold: true
                font.pixelSize: Theme.fs(15)
              }
              Text {
                text: !BluetoothState.available ? "No adapter"
                    : !BluetoothState.powered ? "Off"
                    : BluetoothState.connectedCount > 0
                      ? BluetoothState.connectedCount + " connected" : "On"
                color: Theme.textDim
                font.pixelSize: Theme.fs(11)
              }
            }
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.fs(8)

            Rectangle {
              width: Theme.fs(66)
              height: Theme.fs(28)
              radius: Theme.radiusCell
              color: BluetoothState.powered ? Theme.accent : Theme.surface
              opacity: BluetoothState.available && !BluetoothState.busy
                ? 1 : Theme.opacityDisabled

              Text {
                anchors.centerIn: parent
                text: BluetoothState.powered ? "Disable" : "Enable"
                color: BluetoothState.powered ? Theme.bgDeep : Theme.text
                font.pixelSize: Theme.fs(10)
                font.bold: true
              }
              MouseArea {
                anchors.fill: parent
                enabled: BluetoothState.available && !BluetoothState.busy
                onClicked: BluetoothState.setPower(!BluetoothState.powered)
              }
            }

            Rectangle {
              width: Theme.fs(58)
              height: Theme.fs(28)
              radius: Theme.radiusCell
              color: BluetoothState.scanning ? Theme.accent : "transparent"
              border.width: Theme.borderWidth
              border.color: BluetoothState.scanning ? Theme.accent : Theme.surface
              opacity: BluetoothState.powered && !BluetoothState.busy
                ? 1 : Theme.opacityDisabled

              Text {
                anchors.centerIn: parent
                text: BluetoothState.busyAction === "scan" ? "Scanning" : "Scan"
                color: BluetoothState.scanning ? Theme.bgDeep : Theme.text
                font.pixelSize: Theme.fs(10)
                font.bold: true
              }
              MouseArea {
                anchors.fill: parent
                enabled: BluetoothState.powered && !BluetoothState.busy
                onClicked: BluetoothState.scan()
              }
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.surface }

        Text {
          width: parent.width
          visible: BluetoothState.lastError !== ""
          text: BluetoothState.lastError
          color: Theme.error
          font.pixelSize: Theme.fs(10)
          wrapMode: Text.Wrap
        }

        Item {
          width: parent.width
          height: Theme.fs(16)
          Text {
            anchors.left: parent.left
            text: "DEVICES"
            color: Theme.textDim
            font.pixelSize: Theme.fs(10)
            font.bold: true
          }
          Text {
            anchors.right: parent.right
            text: BluetoothState.devices.length + " known"
            color: Theme.textMuted
            font.pixelSize: Theme.fs(10)
          }
        }

        Item {
          width: parent.width
          height: Theme.fs(338)

          ListView {
            id: deviceList
            anchors.fill: parent
            clip: true
            spacing: Theme.fs(6)
            model: BluetoothState.devices

            delegate: Rectangle {
              id: deviceRow
              required property var modelData
              width: ListView.view.width
              height: Theme.fs(62)
              radius: Theme.radiusRow
              color: Theme.surface

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.fs(10)
                anchors.verticalCenter: parent.verticalCenter
                text: deviceRow.modelData.connected ? String.fromCodePoint(0xf00b1)
                      : String.fromCodePoint(0xf00af)
                font.family: Theme.glyphFamily
                font.pixelSize: Theme.fs(18)
                color: deviceRow.modelData.connected ? Theme.accent : Theme.textDim
              }

              Column {
                anchors.left: parent.left
                anchors.leftMargin: Theme.fs(42)
                anchors.right: actionButton.left
                anchors.rightMargin: Theme.fs(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.fs(2)

                Text {
                  width: parent.width
                  text: deviceRow.modelData.name
                  color: Theme.text
                  font.pixelSize: Theme.fs(12)
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: (deviceRow.modelData.connected ? "Connected"
                      : deviceRow.modelData.paired ? "Paired" : "Discovered")
                      + "  •  " + deviceRow.modelData.address
                  color: Theme.textMuted
                  font.pixelSize: Theme.fs(9)
                  elide: Text.ElideRight
                }
              }

              Rectangle {
                id: actionButton
                anchors.right: parent.right
                anchors.rightMargin: Theme.fs(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fs(deviceRow.modelData.connected ? 78 : 62)
                height: Theme.fs(28)
                radius: Theme.radiusCell
                color: deviceRow.modelData.connected ? "transparent" : Theme.accent
                border.width: Theme.borderWidth
                border.color: deviceRow.modelData.connected ? Theme.surfaceAlt : Theme.accent
                opacity: BluetoothState.powered && !BluetoothState.busy
                  ? 1 : Theme.opacityDisabled

                Text {
                  anchors.centerIn: parent
                  text: BluetoothState.pendingAddress === deviceRow.modelData.address
                      ? "Working"
                      : deviceRow.modelData.connected ? "Disconnect"
                      : deviceRow.modelData.paired ? "Connect" : "Pair"
                  color: deviceRow.modelData.connected ? Theme.text : Theme.bgDeep
                  font.pixelSize: Theme.fs(10)
                  font.bold: true
                }
                MouseArea {
                  anchors.fill: parent
                  enabled: BluetoothState.powered && !BluetoothState.busy
                  onClicked: BluetoothState.activateDevice(deviceRow.modelData)
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            width: parent.width - Theme.fs(24)
            visible: BluetoothState.devices.length === 0
            text: !BluetoothState.available ? "No Bluetooth adapter was found"
                : !BluetoothState.powered ? "Enable Bluetooth to view devices"
                : BluetoothState.busyAction === "scan" ? "Scanning for nearby devices…"
                : "No devices found. Select Scan to discover one."
            color: Theme.textMuted
            font.pixelSize: Theme.fs(11)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }
}
