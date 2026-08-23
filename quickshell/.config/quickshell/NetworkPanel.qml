import QtQuick
import Quickshell

PopupWindow {
  id: panel
  required property Item anchorItem
  required property string ownerScreen

  // Only the bar instance whose icon was clicked shows a panel.
  visible: NetworkState.panelVisible
        && NetworkState.panelScreen === panel.ownerScreen
  grabFocus: true

  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: 6

  implicitWidth: Theme.fs(380)
  implicitHeight: Theme.fs(420)

  Rectangle {
    anchors.fill: parent
    color: Theme.bg

    Item {
      id: focusScope
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: NetworkState.panelVisible = false

      Column {
        anchors.fill: parent
        anchors.margins: Theme.fs(16)
        spacing: Theme.fs(14)

        // --- header ---
        Row {
          spacing: Theme.fs(10)
          Text {
            text: NetworkState.connType === "ethernet" ? String.fromCodePoint(0xef44)
                  : String.fromCodePoint(0xf0928)
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(22)
            color: Theme.text
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            spacing: Theme.fs(2)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              text: NetworkState.connType === "ethernet" ? "Ethernet"
                    : NetworkState.connType === "wifi" ? "Wi-Fi" : "Disconnected"
              color: Theme.text
              font.bold: true
              font.pixelSize: Theme.fs(15)
            }
            Text {
              text: NetworkState.connType === "wifi"
                    ? (NetworkState.ssid + " • " + NetworkState.signalPct + "%")
                    : (NetworkState.connType === "ethernet" ? "Connected" : "No connection")
              color: Theme.textDim
              font.pixelSize: Theme.fs(11)
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.surface }

        // --- metrics ---
        Grid {
          columns: 2
          columnSpacing: Theme.fs(24)
          rowSpacing: Theme.fs(12)
          width: parent.width

          Column {
            width: (parent.width - 24) / 2
            spacing: Theme.fs(2)
            Text { text: "Ping"; color: Theme.textDim; font.pixelSize: Theme.fs(11) }
            Text {
              text: NetworkState.pingMs >= 0 ? NetworkState.pingMs.toFixed(0) + " ms" : "-"
              color: Theme.text; font.pixelSize: Theme.fs(14)
            }
          }
          Column {
            width: (parent.width - 24) / 2
            spacing: Theme.fs(2)
            Text { text: "Packet Loss"; color: Theme.textDim; font.pixelSize: Theme.fs(11) }
            Text {
              text: NetworkState.packetLossPct >= 0 ? NetworkState.packetLossPct.toFixed(0) + " %" : "-"
              color: Theme.text; font.pixelSize: Theme.fs(14)
            }
          }

          Column {
            width: (parent.width - 24) / 2
            spacing: Theme.fs(2)
            Text { text: "Receiving"; color: Theme.textDim; font.pixelSize: Theme.fs(11) }
            Text { text: NetworkState.formatBytes(NetworkState.rxRate) + "/s"; color: Theme.text; font.pixelSize: Theme.fs(14) }
          }
          Column {
            width: (parent.width - 24) / 2
            spacing: Theme.fs(2)
            Text { text: "Sending"; color: Theme.textDim; font.pixelSize: Theme.fs(11) }
            Text { text: NetworkState.formatBytes(NetworkState.txRate) + "/s"; color: Theme.text; font.pixelSize: Theme.fs(14) }
          }

          Column {
            width: (parent.width - 24) / 2
            spacing: Theme.fs(2)
            Text { text: "Downloaded"; color: Theme.textDim; font.pixelSize: Theme.fs(11) }
            Text { text: NetworkState.formatBytes(NetworkState.rxTotal); color: Theme.text; font.pixelSize: Theme.fs(14) }
          }
          Column {
            width: (parent.width - 24) / 2
            spacing: Theme.fs(2)
            Text { text: "Uploaded"; color: Theme.textDim; font.pixelSize: Theme.fs(11) }
            Text { text: NetworkState.formatBytes(NetworkState.txTotal); color: Theme.text; font.pixelSize: Theme.fs(14) }
          }

          Column {
            width: (parent.width - 24) / 2
            spacing: Theme.fs(2)
            Text { text: "IP Address"; color: Theme.textDim; font.pixelSize: Theme.fs(11) }
            Text { text: NetworkState.ipAddress; color: Theme.text; font.pixelSize: Theme.fs(14) }
          }
          Column {
            width: (parent.width - 24) / 2
            spacing: Theme.fs(2)
            Text { text: "Gateway"; color: Theme.textDim; font.pixelSize: Theme.fs(11) }
            Text { text: NetworkState.gateway; color: Theme.text; font.pixelSize: Theme.fs(14) }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.surface }

        // --- DNS provider ---
        Column {
          width: parent.width
          spacing: Theme.fs(8)

          Text { text: "DNS Provider"; color: Theme.textDim; font.pixelSize: Theme.fs(11) }

          Row {
            spacing: Theme.fs(6)

            Repeater {
              model: NetworkState.dnsProviders

              Rectangle {
                width: Theme.fs(78)
                height: Theme.fs(28)
                radius: Theme.fs(5)
                readonly property bool isActive: NetworkState.activeProviderId === modelData.id
                color: isActive ? Theme.accent : Theme.surface

                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  font.pixelSize: Theme.fs(11)
                  color: parent.isActive ? Theme.bgDeep : Theme.text
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: NetworkState.applyDns(modelData.id)
                }
              }
            }

            Rectangle {
              width: Theme.fs(78)
              height: Theme.fs(28)
              radius: Theme.fs(5)
              readonly property bool isActive: NetworkState.activeProviderId === "custom"
              color: isActive ? Theme.accent : Theme.surface

              Text {
                anchors.centerIn: parent
                text: "Custom"
                font.pixelSize: Theme.fs(11)
                color: parent.isActive ? Theme.bgDeep : Theme.text
              }

              MouseArea {
                anchors.fill: parent
                onClicked: customDnsRow.visible = !customDnsRow.visible
              }
            }
          }

          Row {
            id: customDnsRow
            visible: false
            spacing: Theme.fs(6)
            width: parent.width

            Rectangle {
              width: Theme.fs(180)
              height: Theme.fs(26)
              radius: Theme.fs(4)
              color: Theme.bgDeep
              border.color: Theme.surface

              TextInput {
                id: customDnsInput
                anchors.fill: parent
                anchors.leftMargin: Theme.fs(8)
                anchors.rightMargin: Theme.fs(8)
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.pixelSize: Theme.fs(12)
                text: NetworkState.customDnsIp
                onTextChanged: NetworkState.customDnsIp = text
                onAccepted: NetworkState.applyDns("custom")
              }
            }

            Rectangle {
              width: Theme.fs(52)
              height: Theme.fs(26)
              radius: Theme.fs(4)
              color: Theme.surface
              Text { anchors.centerIn: parent; text: "Apply"; color: Theme.text; font.pixelSize: Theme.fs(11) }
              MouseArea { anchors.fill: parent; onClicked: NetworkState.applyDns("custom") }
            }
          }

          Text {
            visible: NetworkState.dnsChanging || NetworkState.dnsError !== ""
            text: NetworkState.dnsChanging ? "Applying…" : NetworkState.dnsError
            color: NetworkState.dnsError !== "" ? Theme.error : Theme.textDim
            font.pixelSize: Theme.fs(11)
          }
        }
      }
    }
  }

  onVisibleChanged: if (visible) focusScope.forceActiveFocus()
}
