import QtQuick
import Quickshell

// Bluetooth menu. Follows the popup conventions of the other bar panels:
// anchored under its bar item, focus-grabbing, Escape closes, visible only on
// the screen whose icon was clicked, and sized to its content like AudioPanel
// and NetworkPanel rather than reserving a fixed box.
//
// Built around one job: reconnecting a device you already own. Connected
// devices get a hero card, paired-but-idle devices a compact list, and
// discovery stays folded away behind a button until you actually want to pair
// something. Interaction is pointer-only apart from Escape; each zone is fed
// by its own incrementally-synced model in BluetoothState, so a connect moves
// a row between zones and a battery poll repaints one line.
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
  anchor.margins.top: Theme.gapS

  implicitWidth: Theme.fs(400)
  readonly property int maxHeight: Theme.fs(620)
  implicitHeight: Math.min(panel.maxHeight, body.implicitHeight + Theme.gapL * 2)

  Behavior on implicitHeight {
    NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
  }

  // Adapter-level trouble belongs in the header banner; a failed connect or
  // pair belongs on the row that failed, which renders it itself.
  readonly property bool adapterError: BluetoothState.lastError !== ""
                                    && BluetoothState.errorAddress === ""

  readonly property string emptyMessage: {
    if (!BluetoothState.available)
      return "No Bluetooth adapter was found"
    if (!BluetoothState.powered)
      return "Bluetooth is off"
    if (BluetoothState.connected.count > 0 || BluetoothState.paired.count > 0)
      return ""
    return "Nothing paired yet"
  }

  // Shared by all three zone lists: rows fade and slide rather than popping,
  // during a scan and as devices move between zones.
  readonly property Transition rowEnter: Transition {
    NumberAnimation {
      properties: "opacity"
      from: 0
      to: 1
      duration: Theme.animFast
      easing.type: Easing.OutCubic
    }
  }
  readonly property Transition rowExit: Transition {
    NumberAnimation {
      properties: "opacity"
      to: 0
      duration: Theme.animFast
      easing.type: Easing.OutCubic
    }
  }
  readonly property Transition rowDisplaced: Transition {
    NumberAnimation {
      properties: "y"
      duration: Theme.animFast
      easing.type: Easing.OutCubic
    }
  }

  onVisibleChanged: if (visible) keys.forceActiveFocus()

  Rectangle {
    anchors.fill: parent
    color: Theme.bg

    FocusScope {
      id: keys
      anchors.fill: parent
      focus: true
      // The only key binding left: this is a pointer-driven popup, but Escape
      // is what every popup on the desktop honours.
      Keys.onEscapePressed: BluetoothState.panelVisible = false

      Flickable {
        anchors.fill: parent
        anchors.margins: Theme.gapL
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: body
          width: parent.width
          spacing: Theme.gapM

          // --- header ----------------------------------------------------------

          Item {
            width: parent.width
            height: Theme.fs(34)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.gapS

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: BluetoothState.glyph
                font.family: Theme.glyphFamily
                font.pixelSize: Theme.fs(22)
                color: BluetoothState.connectedCount > 0 ? Theme.accent
                     : BluetoothState.powered ? Theme.text : Theme.textMuted
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.fs(2)

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

            Rectangle {
              id: powerButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Theme.fs(74)
              height: Theme.fs(28)
              radius: Theme.radiusCell
              color: BluetoothState.powered
                ? (powerArea.containsMouse ? Theme.accentAlt : Theme.accent)
                : (powerArea.containsMouse ? Theme.surfaceAlt : Theme.surface)
              opacity: powerArea.enabled ? 1 : Theme.opacityDisabled

              Behavior on color {
                ColorAnimation { duration: Theme.animFast }
              }

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
          }

          // --- adapter error banner --------------------------------------------

          Row {
            width: parent.width
            spacing: Theme.gapXS
            visible: panel.adapterError

            Text {
              text: BluetoothState.glyphError
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(12)
              color: Theme.error
            }
            Text {
              width: parent.width - Theme.fs(20)
              text: BluetoothState.lastError
              color: Theme.error
              font.pixelSize: Theme.fs(10)
              wrapMode: Text.Wrap
            }
          }

          // --- zone 1: connected -----------------------------------------------
          //
          // When there is nothing to show here the state message takes the
          // hero's place, so the panel keeps its silhouette instead of
          // swapping layouts between off, empty and in-use.

          Rectangle {
            width: parent.width
            height: Theme.fs(62)
            radius: Theme.radiusRow
            color: Theme.bgDeep
            visible: panel.emptyMessage !== ""

            Text {
              anchors.centerIn: parent
              width: parent.width - Theme.gapL * 2
              text: panel.emptyMessage
              color: Theme.textMuted
              font.pixelSize: Theme.fs(11)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
            }
          }

          // A ListView rather than a Repeater so a device connecting or
          // disconnecting animates into and out of the zone: that movement is
          // the feedback that the row you clicked went somewhere.
          ListView {
            width: parent.width
            height: contentHeight
            interactive: false
            spacing: Theme.gapS
            model: BluetoothState.connected

            add: panel.rowEnter
            remove: panel.rowExit
            displaced: panel.rowDisplaced

            delegate: BluetoothHeroCard {
              required property var model

              width: ListView.view.width
              address: model.address
              name: model.name
              icon: model.icon
              battery: model.battery
            }
          }

          // --- zone 2: paired, idle --------------------------------------------

          Column {
            width: parent.width
            spacing: Theme.gapS
            visible: BluetoothState.paired.count > 0

            Text {
              text: "MY DEVICES"
              color: Theme.textDim
              font.pixelSize: Theme.fs(10)
              font.bold: true
            }

            Column {
              width: parent.width
              spacing: Theme.gapXS

              ListView {
                width: parent.width
                height: contentHeight
                interactive: false
                spacing: Theme.gapXS
                model: BluetoothState.paired

                add: panel.rowEnter
                remove: panel.rowExit
                displaced: panel.rowDisplaced

                delegate: BluetoothDeviceRow {
                  required property var model

                  width: ListView.view.width
                  address: model.address
                  name: model.name
                  paired: model.paired
                  connected: model.connected
                  trusted: model.trusted
                  icon: model.icon
                  battery: model.battery
                }
              }
            }
          }

          // --- zone 3: discovery -----------------------------------------------
          //
          // Folded away by default. Expanding it starts a scan, because
          // opening a discovery section has exactly one meaning; the scan
          // lapses on its own so a forgotten open panel does not hold the
          // radio in discovery.

          Column {
            width: parent.width
            spacing: Theme.gapS
            visible: BluetoothState.powered

            Rectangle {
              id: discoveryButton
              width: parent.width
              height: Theme.fs(32)
              radius: Theme.radiusCell
              color: discoveryArea.containsMouse ? Theme.surface : "transparent"
              border.width: Theme.borderWidth
              border.color: BluetoothState.discoveryExpanded
                ? Theme.accent : Theme.surface

              Behavior on color {
                ColorAnimation { duration: Theme.animFast }
              }

              Row {
                anchors.centerIn: parent
                spacing: Theme.gapXS

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: BluetoothState.glyphScan
                  font.family: Theme.glyphFamily
                  font.pixelSize: Theme.fs(13)
                  color: BluetoothState.scanActive ? Theme.accent : Theme.textDim

                  RotationAnimator on rotation {
                    running: BluetoothState.scanActive
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 2400
                  }
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: !BluetoothState.discoveryExpanded
                      ? "Scan for new devices"
                      : BluetoothState.scanActive ? "Scanning…" : "Scan again"
                  color: Theme.text
                  font.pixelSize: Theme.fs(11)
                  font.bold: true
                }
              }

              MouseArea {
                id: discoveryArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  // Open-and-scan, rescan, or fold away: the button carries
                  // all three because they are the same intent at different
                  // points in the flow.
                  if (!BluetoothState.discoveryExpanded)
                    BluetoothState.setDiscoveryExpanded(true)
                  else if (!BluetoothState.scanActive)
                    BluetoothState.startScan()
                  else
                    BluetoothState.setDiscoveryExpanded(false)
                }
              }
            }

            Column {
              width: parent.width
              spacing: Theme.gapXS
              visible: BluetoothState.discoveryExpanded

              Text {
                visible: BluetoothState.discovered.count === 0
                text: BluetoothState.scanActive
                  ? "Looking for nearby devices…"
                  : "Nothing new found. Scan again, or put the device into pairing mode."
                width: parent.width
                color: Theme.textMuted
                font.pixelSize: Theme.fs(10)
                wrapMode: Text.Wrap
              }

              ListView {
                width: parent.width
                height: contentHeight
                interactive: false
                spacing: Theme.gapXS
                model: BluetoothState.discovered

                add: panel.rowEnter
                remove: panel.rowExit
                displaced: panel.rowDisplaced

                delegate: BluetoothDeviceRow {
                  required property var model

                  width: ListView.view.width
                  address: model.address
                  name: model.name
                  paired: model.paired
                  connected: model.connected
                  trusted: model.trusted
                  icon: model.icon
                  battery: model.battery
                }
              }
            }
          }
        }
      }
    }
  }
}
