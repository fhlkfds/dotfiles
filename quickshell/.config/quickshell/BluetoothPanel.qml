import QtQuick
import Quickshell

// Bluetooth menu. Follows the popup conventions of the other bar panels:
// anchored under its bar item, focus-grabbing, Escape closes, visible only on
// the screen whose icon was clicked.
//
// The device list is fully keyboard navigable and is fed by a ListModel that
// BluetoothState keeps in sync per-row, so a poll that only changes one
// battery reading repaints one row.
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

  implicitWidth: Theme.fs(420)
  implicitHeight: Theme.fs(500)

  readonly property int rowHeight: Theme.fs(58)

  function labelFor(action) {
    switch (action) {
      case "connect": return "Connect"
      case "disconnect": return "Disconnect"
      case "pair": return "Pair"
      case "trust": return "Trusting"
      case "untrust": return "Untrusting"
      case "forget": return "Removing"
      case "power": return "Power"
      default: return action
    }
  }

  onVisibleChanged: {
    if (!visible)
      return
    if (BluetoothState.selectedAddress === "" && BluetoothState.devices.length > 0)
      BluetoothState.selectedAddress = BluetoothState.devices[0].address
    keys.forceActiveFocus()
  }

  Rectangle {
    anchors.fill: parent
    color: Theme.bg

    FocusScope {
      id: keys
      anchors.fill: parent
      anchors.margins: Theme.fs(16)
      focus: true

      Keys.onEscapePressed: BluetoothState.panelVisible = false
      Keys.onUpPressed: BluetoothState.moveSelection(-1)
      Keys.onDownPressed: BluetoothState.moveSelection(1)
      Keys.onReturnPressed: BluetoothState.activateDevice(BluetoothState.selected)
      Keys.onEnterPressed: BluetoothState.activateDevice(BluetoothState.selected)

      Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) {
          BluetoothState.selectEdge(false)
        } else if (event.key === Qt.Key_End) {
          BluetoothState.selectEdge(true)
        } else if (event.key === Qt.Key_PageUp) {
          BluetoothState.moveSelection(-5)
        } else if (event.key === Qt.Key_PageDown) {
          BluetoothState.moveSelection(5)
        // Destructive and adapter-wide actions take Ctrl, matching the
        // Ctrl+Delete the clipboard panel already uses to remove an entry.
        } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ControlModifier)) {
          BluetoothState.forgetDevice(BluetoothState.selected)
        } else if (event.key === Qt.Key_T && (event.modifiers & Qt.ControlModifier)) {
          BluetoothState.toggleTrust(BluetoothState.selected)
        } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
          if (BluetoothState.powered)
            BluetoothState.toggleScan()
        } else if (event.key === Qt.Key_B && (event.modifiers & Qt.ControlModifier)) {
          if (BluetoothState.available)
            BluetoothState.setPower(!BluetoothState.powered)
        } else {
          return
        }
        event.accepted = true
      }

      // --- header --------------------------------------------------------------

      Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Theme.fs(36)

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.gapS

          Text {
            text: BluetoothState.glyph
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(22)
            color: BluetoothState.connectedCount > 0 ? Theme.accent
                 : BluetoothState.powered ? Theme.text : Theme.textMuted
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
                  : BluetoothState.adapterBusy ? "Switching…"
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
          spacing: Theme.gapS

          Rectangle {
            id: powerButton
            width: Theme.fs(72)
            height: Theme.fs(28)
            radius: Theme.radiusCell
            color: BluetoothState.powered
              ? (powerArea.containsMouse ? Theme.accentAlt : Theme.accent)
              : (powerArea.containsMouse ? Theme.surfaceAlt : Theme.surface)
            opacity: powerArea.enabled ? 1 : Theme.opacityDisabled

            Text {
              anchors.centerIn: parent
              text: BluetoothState.adapterBusy ? "…"
                  : BluetoothState.powered ? "Disable" : "Enable"
              color: BluetoothState.powered ? Theme.bgDeep : Theme.text
              font.pixelSize: Theme.fs(10)
              font.bold: true
            }
            MouseArea {
              id: powerArea
              anchors.fill: parent
              hoverEnabled: true
              enabled: BluetoothState.available && !BluetoothState.adapterBusy
              onClicked: BluetoothState.setPower(!BluetoothState.powered)
            }
          }

          Rectangle {
            id: scanButton
            readonly property bool active: BluetoothState.scanning
                                        || BluetoothState.scanRequested
            width: Theme.fs(78)
            height: Theme.fs(28)
            radius: Theme.radiusCell
            color: active ? Theme.accent
                 : scanArea.containsMouse ? Theme.surface : "transparent"
            border.width: Theme.borderWidth
            border.color: active ? Theme.accent : Theme.surface
            opacity: scanArea.enabled ? 1 : Theme.opacityDisabled

            Row {
              anchors.centerIn: parent
              spacing: Theme.gapXS

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: BluetoothState.glyphScan
                font.family: Theme.glyphFamily
                font.pixelSize: Theme.fs(12)
                color: scanButton.active ? Theme.bgDeep : Theme.text

                RotationAnimator on rotation {
                  running: scanButton.active
                  loops: Animation.Infinite
                  from: 0
                  to: 360
                  duration: 2400
                }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: scanButton.active ? "Stop" : "Scan"
                color: scanButton.active ? Theme.bgDeep : Theme.text
                font.pixelSize: Theme.fs(10)
                font.bold: true
              }
            }

            MouseArea {
              id: scanArea
              anchors.fill: parent
              hoverEnabled: true
              enabled: BluetoothState.powered
              onClicked: BluetoothState.toggleScan()
            }
          }
        }
      }

      Rectangle {
        id: divider
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: Theme.gapM
        height: 1
        color: Theme.surface
      }

      // --- error banner --------------------------------------------------------

      Row {
        id: banner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: divider.bottom
        anchors.topMargin: visible ? Theme.gapS : 0
        height: visible ? implicitHeight : 0
        spacing: Theme.gapXS
        visible: BluetoothState.lastError !== ""

        Text {
          text: BluetoothState.glyphError
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(12)
          color: Theme.error
        }
        Text {
          width: banner.width - Theme.fs(20)
          text: BluetoothState.lastError
          color: Theme.error
          font.pixelSize: Theme.fs(10)
          wrapMode: Text.Wrap
        }
      }

      // --- section header ------------------------------------------------------

      Item {
        id: section
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: banner.bottom
        anchors.topMargin: Theme.gapM
        height: Theme.fs(16)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "DEVICES"
          color: Theme.textDim
          font.pixelSize: Theme.fs(10)
          font.bold: true
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: {
            const total = BluetoothState.devices.length
            const connected = BluetoothState.connectedCount
            const known = total + (total === 1 ? " device" : " devices")
            return connected > 0 ? known + "  •  " + connected + " connected" : known
          }
          color: Theme.textMuted
          font.pixelSize: Theme.fs(10)
        }
      }

      // --- device list ---------------------------------------------------------

      ListView {
        id: deviceList
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: section.bottom
        anchors.bottom: hint.top
        anchors.topMargin: Theme.gapS
        anchors.bottomMargin: Theme.gapS
        clip: true
        spacing: Theme.gapXS
        model: BluetoothState.model
        // Keys are handled by the enclosing focus scope, which owns selection.
        keyNavigationEnabled: false
        currentIndex: BluetoothState.selectedIndex

        onCurrentIndexChanged:
          if (currentIndex >= 0)
            deviceList.positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Rectangle {
          id: deviceRow

          required property int index
          required property string address
          required property string name
          required property bool paired
          required property bool connected
          required property bool trusted
          required property string icon
          required property int battery

          // Rebuilt as a plain object so the state helpers, which are written
          // against the poll's device shape, can be reused unchanged.
          readonly property var device: ({
            address: deviceRow.address, name: deviceRow.name,
            paired: deviceRow.paired, connected: deviceRow.connected,
            trusted: deviceRow.trusted, icon: deviceRow.icon,
            battery: deviceRow.battery
          })

          readonly property bool isCurrent: index === BluetoothState.selectedIndex
          readonly property string pending: BluetoothState.pendingFor(deviceRow.address)
          readonly property bool busy: pending !== ""

          width: ListView.view.width
          height: panel.rowHeight
          radius: Theme.radiusRow
          color: isCurrent || rowArea.containsMouse ? Theme.surface : Theme.bgDeep
          border.width: Theme.borderWidth
          border.color: isCurrent ? Theme.accent : "transparent"

          MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            // Below the row's own buttons so they keep their clicks.
            z: -1
            onClicked: BluetoothState.selectedAddress = deviceRow.address
          }

          Text {
            id: typeGlyph
            anchors.left: parent.left
            anchors.leftMargin: Theme.gapM
            anchors.verticalCenter: parent.verticalCenter
            text: BluetoothState.glyphForDevice(deviceRow.device)
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(18)
            color: deviceRow.connected ? Theme.accent
                 : deviceRow.paired ? Theme.textDim : Theme.textMuted
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
              text: deviceRow.name
                  + (deviceRow.connected && deviceRow.battery >= 0
                     ? " — " + deviceRow.battery + "%" : "")
              color: Theme.text
              font.pixelSize: Theme.fs(12)
              font.bold: true
              elide: Text.ElideRight
            }

            Row {
              width: parent.width
              spacing: Theme.gapXS

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: deviceRow.busy ? panel.labelFor(deviceRow.pending) + "…"
                    : deviceRow.connected ? "Connected"
                    : deviceRow.paired ? "Paired" : "Available"
                color: deviceRow.busy ? Theme.warning
                     : deviceRow.connected ? Theme.success
                     : deviceRow.paired ? Theme.textDim : Theme.textMuted
                font.pixelSize: Theme.fs(9)
                font.bold: true
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "•"
                color: Theme.textMuted
                font.pixelSize: Theme.fs(9)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: deviceRow.address
                color: Theme.textMuted
                font.pixelSize: Theme.fs(9)
                elide: Text.ElideRight
              }
            }
          }

          Row {
            id: actions
            anchors.right: parent.right
            anchors.rightMargin: Theme.gapM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gapXS

            // Trust and forget only apply once a device is known to BlueZ.
            IconButton {
              anchors.verticalCenter: parent.verticalCenter
              size: Theme.fs(28)
              glyphSize: Theme.fs(13)
              visible: deviceRow.paired
              glyph: deviceRow.trusted
                ? BluetoothState.glyphTrusted : BluetoothState.glyphUntrusted
              active: deviceRow.trusted
              enabled: !deviceRow.busy
              onClicked: BluetoothState.toggleTrust(deviceRow.device)
            }

            IconButton {
              anchors.verticalCenter: parent.verticalCenter
              size: Theme.fs(28)
              glyphSize: Theme.fs(13)
              visible: deviceRow.paired
              glyph: BluetoothState.glyphForget
              enabled: !deviceRow.busy
              onClicked: BluetoothState.forgetDevice(deviceRow.device)
            }

            Rectangle {
              id: actionButton
              anchors.verticalCenter: parent.verticalCenter
              width: Theme.fs(deviceRow.connected ? 84 : 66)
              height: Theme.fs(28)
              radius: Theme.radiusCell
              color: deviceRow.connected
                ? (actionArea.containsMouse ? Theme.surfaceAlt : "transparent")
                : (actionArea.containsMouse ? Theme.accentAlt : Theme.accent)
              border.width: Theme.borderWidth
              border.color: deviceRow.connected ? Theme.surfaceAlt : Theme.accent
              opacity: actionArea.enabled ? 1 : Theme.opacityDisabled

              Row {
                anchors.centerIn: parent
                spacing: Theme.gapXS

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: deviceRow.busy
                  text: BluetoothState.glyphPending
                  font.family: Theme.glyphFamily
                  font.pixelSize: Theme.fs(11)
                  color: deviceRow.connected ? Theme.text : Theme.bgDeep

                  RotationAnimator on rotation {
                    running: deviceRow.busy
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 1000
                  }
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: deviceRow.busy
                      ? panel.labelFor(deviceRow.pending)
                      : panel.labelFor(BluetoothState.primaryAction(deviceRow.device))
                  color: deviceRow.connected ? Theme.text : Theme.bgDeep
                  font.pixelSize: Theme.fs(10)
                  font.bold: true
                }
              }

              MouseArea {
                id: actionArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: BluetoothState.powered && !deviceRow.busy
                onClicked: {
                  BluetoothState.selectedAddress = deviceRow.address
                  BluetoothState.activateDevice(deviceRow.device)
                }
              }
            }
          }
        }
      }

      // --- empty state ---------------------------------------------------------

      Text {
        anchors.centerIn: deviceList
        width: deviceList.width - Theme.fs(24)
        visible: BluetoothState.model.count === 0
        text: !BluetoothState.available ? "No Bluetooth adapter was found"
            : !BluetoothState.powered ? "Enable Bluetooth to view devices"
            : (BluetoothState.scanning || BluetoothState.scanRequested)
              ? "Scanning for nearby devices…"
            : "No devices yet. Select Scan to discover one."
        color: Theme.textMuted
        font.pixelSize: Theme.fs(11)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
      }

      // --- key hints -----------------------------------------------------------

      Text {
        id: hint
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: "↑↓ select   ⏎ connect   ^T trust   ^Del forget   ^S scan   Esc close"
        color: Theme.textFaint
        font.pixelSize: Theme.fs(9)
        elide: Text.ElideRight
      }
    }
  }
}
