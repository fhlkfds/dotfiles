import QtQuick
import Quickshell

// Expanded media panel: artwork left, metadata / timeline / controls centre,
// lyrics right. Follows the popup conventions of AudioPanel and NetworkPanel.
PopupWindow {
  id: panel
  required property Item anchorItem
  required property string ownerScreen

  // Only the bar instance whose icon was clicked shows a panel.
  visible: MediaState.panelVisible
        && MediaState.panelScreen === panel.ownerScreen
  grabFocus: true

  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: 6

  implicitWidth: Theme.fs(900)
  implicitHeight: Theme.fs(340)

  readonly property int artSize: Theme.fs(220)
  readonly property int lyricsWidth: Theme.fs(330)
  readonly property int columnSpacing: Theme.fs(16)

  Rectangle {
    anchors.fill: parent
    color: Theme.bg

    Item {
      id: focusScope
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: MediaState.panelVisible = false

      // --- EMPTY STATE ---
      Text {
        anchors.centerIn: parent
        visible: !MediaState.hasTrack
        text: "Nothing playing"
        color: Theme.textMuted
        font.pixelSize: Theme.fs(13)
      }

      Item {
        anchors.fill: parent
        anchors.margins: Theme.panelMargin
        visible: MediaState.hasTrack

        Row {
          id: columns
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: panel.columnSpacing

          // ================= ARTWORK =================
          Rectangle {
            id: artFrame
            width: panel.artSize
            height: panel.artSize
            radius: Theme.radiusCell
            color: Theme.surface
            clip: true

            // Two layers so a new cover fades over the old one. The incoming
            // URL is loaded into whichever layer is currently behind, and the
            // layers only swap once it has actually decoded -- so a slow or
            // broken fetch never blanks the artwork.
            readonly property string url: MediaState.trackArtUrl
            property bool showA: true
            readonly property Image front: showA ? imgA : imgB
            readonly property Image back: showA ? imgB : imgA

            onUrlChanged: if (url !== "") back.source = url

            function layerReady(img) {
              if (img === artFrame.back)
                artFrame.showA = !artFrame.showA
            }

            Text {
              anchors.centerIn: parent
              visible: artFrame.front.status !== Image.Ready
              text: MediaState.glyphMusic
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(48)
              color: Theme.textMuted
            }

            // cache: true plus keying on the URL means identical artwork is
            // never re-downloaded when returning to a track.
            Image {
              id: imgA
              anchors.fill: parent
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              cache: true
              opacity: artFrame.showA ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: 220 } }
              onStatusChanged: if (status === Image.Ready) artFrame.layerReady(imgA)
            }

            Image {
              id: imgB
              anchors.fill: parent
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              cache: true
              opacity: artFrame.showA ? 0 : 1
              Behavior on opacity { NumberAnimation { duration: 220 } }
              onStatusChanged: if (status === Image.Ready) artFrame.layerReady(imgB)
            }

            Component.onCompleted: if (artFrame.url !== "") artFrame.back.source = artFrame.url
          }

          // ================= CENTRE =================
          Column {
            width: columns.width - panel.artSize - panel.lyricsWidth
                   - panel.columnSpacing * 2
            spacing: Theme.fs(6)

            Text {
              width: parent.width
              text: MediaState.trackTitle
              color: Theme.text
              font.bold: true
              font.pixelSize: Theme.fs(19)
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: MediaState.trackArtist
              color: Theme.textDim
              font.pixelSize: Theme.fs(14)
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: MediaState.trackAlbum
              color: Theme.textMuted
              font.pixelSize: Theme.fs(12)
              elide: Text.ElideRight
            }

            Item { width: 1; height: Theme.fs(6) }

            // --- TIMELINE ---
            Item {
              width: parent.width
              height: Theme.fs(16)
              opacity: MediaState.canSeek ? 1 : 0.5

              Text {
                id: elapsed
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: MediaState.formatTime(MediaState.effectivePosition)
                color: Theme.textDim
                font.pixelSize: Theme.fs(10)
              }

              Text {
                id: total
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: MediaState.formatTime(MediaState.length)
                color: Theme.textDim
                font.pixelSize: Theme.fs(10)
              }

              VolumeSlider {
                id: seekBar
                anchors.left: elapsed.right
                anchors.right: total.left
                anchors.leftMargin: Theme.fs(8)
                anchors.rightMargin: Theme.fs(8)
                anchors.verticalCenter: parent.verticalCenter
                enabled: MediaState.canSeek
                value: MediaState.progress
                onMoved: fraction => MediaState.seekToFraction(fraction)
              }

              // Suppress incoming position updates while scrubbing so the
              // handle does not fight the player.
              Binding {
                target: MediaState
                property: "dragging"
                value: seekBar.dragging
              }
            }

            // --- CONTROLS ---
            Row {
              spacing: Theme.fs(7)

              IconButton {
                size: Theme.fs(36)
                glyphSize: Theme.fs(18)
                glyph: MediaState.glyphPrevious
                enabled: MediaState.canPrevious
                onClicked: MediaState.previous()
              }

              IconButton {
                size: Theme.fs(36)
                glyphSize: Theme.fs(18)
                glyph: MediaState.playGlyph
                enabled: MediaState.canTogglePlaying
                onClicked: MediaState.togglePlaying()
              }

              IconButton {
                size: Theme.fs(36)
                glyphSize: Theme.fs(18)
                glyph: MediaState.glyphNext
                enabled: MediaState.canNext
                onClicked: MediaState.next()
              }

              IconButton {
                size: Theme.fs(36)
                glyphSize: Theme.fs(18)
                glyph: MediaState.glyphStop
                enabled: MediaState.active !== null
                onClicked: MediaState.stop()
              }

              IconButton {
                size: Theme.fs(36)
                glyphSize: Theme.fs(18)
                glyph: MediaState.loopGlyph
                active: MediaState.loopActive
                enabled: MediaState.loopSupported
                onClicked: MediaState.cycleLoop()
              }

              IconButton {
                size: Theme.fs(36)
                glyphSize: Theme.fs(18)
                glyph: MediaState.shuffleGlyph
                active: MediaState.shuffle
                enabled: MediaState.shuffleSupported
                onClicked: MediaState.toggleShuffle()
              }

              IconButton {
                size: Theme.fs(36)
                glyphSize: Theme.fs(18)
                glyph: MediaState.glyphOpen
                enabled: MediaState.canRaise
                onClicked: MediaState.raisePlayer()
              }
            }

            // --- PLAYER VOLUME (separate from the PipeWire sink volume) ---
            Item {
              width: parent.width
              height: Theme.fs(16)
              visible: MediaState.volumeSupported

              Text {
                id: volGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: MediaState.glyphVolume
                font.family: Theme.glyphFamily
                font.pixelSize: Theme.fs(12)
                color: Theme.textDim
              }

              VolumeSlider {
                anchors.left: volGlyph.right
                anchors.leftMargin: Theme.fs(8)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                value: MediaState.volume
                onMoved: fraction => MediaState.setVolume(fraction)
              }
            }
          }

          // ================= LYRICS =================
          Column {
            width: panel.lyricsWidth
            spacing: Theme.fs(6)

            Item {
              width: parent.width
              height: Theme.fs(14)

              Text {
                anchors.left: parent.left
                text: "LYRICS"
                color: Theme.textDim
                font.pixelSize: Theme.fs(10)
                font.bold: true
              }

              Text {
                anchors.right: parent.right
                text: LyricsState.status === "synced" ? "LRCLIB · SYNCED"
                    : LyricsState.status === "plain" ? "LRCLIB · PLAIN" : "LRCLIB"
                color: Theme.textMuted
                font.pixelSize: Theme.fs(9)
              }
            }

            LyricsView {
              width: parent.width
              height: panel.artSize + Theme.fs(28)
            }
          }
        }

        // ================= SOURCE / PLAYER SELECTOR =================
        Column {
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Theme.fs(4)

          Rectangle {
            id: sourceChip
            width: Theme.fs(240)
            height: Theme.fs(28)
            radius: Theme.radiusRow
            color: Theme.surface

            Text {
              id: sourceIcon
              anchors.left: parent.left
              anchors.leftMargin: Theme.fs(8)
              anchors.verticalCenter: parent.verticalCenter
              text: MediaState.sourceGlyph
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(12)
              color: Theme.text
            }

            Text {
              anchors.left: sourceIcon.right
              anchors.leftMargin: Theme.fs(8)
              anchors.right: parent.right
              anchors.rightMargin: Theme.fs(8)
              anchors.verticalCenter: parent.verticalCenter
              text: MediaState.sourceLabel
                  + (MediaState.pinnedDbusName !== "" ? " (pinned)" : "")
              color: Theme.text
              font.pixelSize: Theme.fs(11)
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              onClicked: playerList.visible = !playerList.visible
            }
          }

          // Clicking the source chip switches the active player.
          Column {
            id: playerList
            visible: false
            width: sourceChip.width
            spacing: Theme.fs(2)

            Repeater {
              model: MediaState.players

              Rectangle {
                required property var modelData
                readonly property bool isActive: MediaState.active === modelData
                width: playerList.width
                height: Theme.fs(22)
                radius: Theme.radiusRow
                color: isActive ? Theme.accent : "transparent"

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Theme.fs(8)
                  anchors.right: parent.right
                  anchors.rightMargin: Theme.fs(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.identity
                  color: parent.isActive ? Theme.bgDeep : Theme.text
                  font.pixelSize: Theme.fs(11)
                  elide: Text.ElideRight
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    MediaState.pinPlayer(modelData.dbusName)
                    playerList.visible = false
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  onVisibleChanged: {
    if (visible)
      focusScope.forceActiveFocus()
  }
}
