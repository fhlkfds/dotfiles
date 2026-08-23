import QtQuick
import Quickshell

PopupWindow {
  id: panel
  required property Item anchorItem
  required property string ownerScreen

  // Only the bar instance whose icon was clicked shows a panel.
  visible: AudioState.panelVisible
        && AudioState.panelScreen === panel.ownerScreen
  grabFocus: true

  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: 6

  implicitWidth: Theme.fs(320)
  implicitHeight: layout.implicitHeight + 32

  Rectangle {
    anchors.fill: parent
    color: Theme.bg

    Item {
      id: focusScope
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: AudioState.panelVisible = false

      Column {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.fs(16)
        spacing: Theme.fs(14)

        // --- header ---
        Item {
          width: parent.width
          height: Theme.fs(34)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.fs(10)

            Text {
              text: AudioState.glyph
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(20)
              color: Theme.text
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              spacing: Theme.fs(2)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                text: "Audio"
                color: Theme.text
                font.bold: true
                font.pixelSize: Theme.fs(15)
              }
              Text {
                text: AudioState.muted ? "Muted"
                      : (AudioState.sink ? AudioState.volumePct + "%" : "No output")
                color: Theme.textDim
                font.pixelSize: Theme.fs(11)
              }
            }
          }

          // mute toggle switch
          Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fs(40)
            height: Theme.fs(20)
            radius: Theme.fs(10)
            color: AudioState.muted ? Theme.surface : Theme.accent

            Rectangle {
              width: Theme.fs(16)
              height: Theme.fs(16)
              radius: Theme.fs(8)
              // Inset derived from the track so the knob stays centred at any
              // text scale.
              y: (parent.height - height) / 2
              x: AudioState.muted
                 ? y : parent.width - width - y
              color: Theme.text
            }

            MouseArea {
              anchors.fill: parent
              onClicked: AudioState.toggleMute()
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.surface }

        // --- OUTPUT ---
        Column {
          width: parent.width
          spacing: Theme.fs(8)

          Item {
            width: parent.width
            height: Theme.fs(14)
            Text {
              anchors.left: parent.left
              text: "OUTPUT"
              color: Theme.textDim
              font.pixelSize: Theme.fs(10)
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              text: AudioState.volumePct + "%"
              color: Theme.text
              font.pixelSize: Theme.fs(11)
            }
          }

          VolumeSlider {
            width: parent.width
            value: AudioState.sink && AudioState.sink.audio ? AudioState.sink.audio.volume : 0
            onMoved: fraction => AudioState.setVolume(fraction)
          }

          Rectangle {
            width: parent.width
            height: Theme.fs(28)
            radius: Theme.fs(5)
            color: Theme.surface

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Theme.fs(8)
              anchors.right: parent.right
              anchors.rightMargin: Theme.fs(8)
              anchors.verticalCenter: parent.verticalCenter
              text: AudioState.deviceLabel(AudioState.sink)
              color: Theme.text
              font.pixelSize: Theme.fs(11)
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              onClicked: sinkList.visible = !sinkList.visible
            }
          }

          Column {
            id: sinkList
            visible: false
            width: parent.width
            spacing: Theme.fs(2)

            Repeater {
              model: AudioState.sinks

              Rectangle {
                width: sinkList.width
                height: Theme.fs(26)
                radius: Theme.fs(4)
                readonly property bool isActive: AudioState.sink === modelData
                color: isActive ? Theme.accent : "transparent"

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Theme.fs(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Theme.fs(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: AudioState.deviceLabel(modelData)
                  color: parent.isActive ? Theme.bgDeep : Theme.text
                  font.pixelSize: Theme.fs(11)
                  elide: Text.ElideRight
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    AudioState.setSink(modelData)
                    sinkList.visible = false
                  }
                }
              }
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.surface }

        // --- INPUT ---
        Column {
          width: parent.width
          spacing: Theme.fs(8)

          Item {
            width: parent.width
            height: Theme.fs(14)
            Text {
              anchors.left: parent.left
              text: "INPUT"
              color: Theme.textDim
              font.pixelSize: Theme.fs(10)
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              text: AudioState.inputVolumePct + "%"
              color: Theme.text
              font.pixelSize: Theme.fs(11)
            }
          }

          VolumeSlider {
            width: parent.width
            value: AudioState.source && AudioState.source.audio ? AudioState.source.audio.volume : 0
            onMoved: fraction => AudioState.setInputVolume(fraction)
          }

          Rectangle {
            width: parent.width
            height: Theme.fs(28)
            radius: Theme.fs(5)
            color: Theme.surface

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Theme.fs(8)
              anchors.right: parent.right
              anchors.rightMargin: Theme.fs(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.fs(6)

              Text {
                text: String.fromCodePoint(0xf036c) // md-microphone
                font.family: Theme.glyphFamily
                font.pixelSize: Theme.fs(13)
                color: Theme.textDim
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: AudioState.deviceLabel(AudioState.source)
                color: Theme.text
                font.pixelSize: Theme.fs(11)
                elide: Text.ElideRight
                width: parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: sourceList.visible = !sourceList.visible
            }
          }

          Column {
            id: sourceList
            visible: false
            width: parent.width
            spacing: Theme.fs(2)

            Repeater {
              model: AudioState.sources

              Rectangle {
                width: sourceList.width
                height: Theme.fs(26)
                radius: Theme.fs(4)
                readonly property bool isActive: AudioState.source === modelData
                color: isActive ? Theme.accent : "transparent"

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Theme.fs(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Theme.fs(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: AudioState.deviceLabel(modelData)
                  color: parent.isActive ? Theme.bgDeep : Theme.text
                  font.pixelSize: Theme.fs(11)
                  elide: Text.ElideRight
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    AudioState.setSource(modelData)
                    sourceList.visible = false
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  onVisibleChanged: if (visible) focusScope.forceActiveFocus()
}
