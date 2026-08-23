import QtQuick

// Media page: cover | details+controls | lyrics.
// Intrinsic size from tokens. Backends untouched -- MediaState for playback and
// LyricsState/LyricsView for synced lyrics, the same singletons the bar uses.
Item {
  id: root
  implicitWidth: Theme.mediaPageW
  implicitHeight: Theme.mediaPageH

  Text {
    anchors.centerIn: parent
    visible: !MediaState.hasTrack
    text: "Nothing playing"
    color: Theme.textMuted
    font.pixelSize: Theme.fs(13)
  }

  Row {
    x: 0
    y: 0
    spacing: Theme.gapL
    visible: MediaState.hasTrack

    // --- cover ---
    Rectangle {
      width: Theme.coverSize
      height: Theme.coverSize
      radius: Theme.radiusXL
      color: Theme.surface
      clip: true

      Text {
        anchors.centerIn: parent
        visible: art.status !== Image.Ready
        text: MediaState.glyphMusic
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(56)
        color: Theme.textMuted
      }

      Image {
        id: art
        anchors.fill: parent
        source: MediaState.trackArtUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
      }
    }

    // --- details + controls ---
    Item {
      width: Theme.mediaSideW
      height: root.implicitHeight

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.gapXS

        Text {
          width: parent.width
          text: MediaState.trackTitle
          color: Theme.text
          font.bold: true
          font.pixelSize: Theme.fs(26)
          elide: Text.ElideRight
          maximumLineCount: 2
          wrapMode: Text.WordWrap
        }
        Text {
          width: parent.width
          text: MediaState.trackArtist
          color: Theme.textDim
          font.pixelSize: Theme.fs(17)
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: MediaState.trackAlbum
          color: Theme.textMuted
          font.pixelSize: Theme.fs(13)
          elide: Text.ElideRight
        }
      }

      // timeline + controls anchored to the bottom of the column
      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Theme.gapM

        Item {
          width: parent.width
          height: Theme.fs(20)
          opacity: MediaState.canSeek ? 1 : 0.5

          Text {
            id: elapsed
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: MediaState.formatTime(MediaState.effectivePosition)
            color: Theme.textDim
            font.pixelSize: Theme.fs(11)
          }
          Text {
            id: total
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: MediaState.formatTime(MediaState.length)
            color: Theme.textDim
            font.pixelSize: Theme.fs(11)
          }
          VolumeSlider {
            id: seekBar
            anchors.left: elapsed.right
            anchors.right: total.left
            anchors.leftMargin: Theme.gapS
            anchors.rightMargin: Theme.gapS
            anchors.verticalCenter: parent.verticalCenter
            enabled: MediaState.canSeek
            value: MediaState.progress
            onMoved: fraction => MediaState.seekToFraction(fraction)
          }
          Binding {
            target: MediaState
            property: "dragging"
            value: seekBar.dragging
          }
        }

        // shuffle · previous · play · next · repeat
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Theme.gapS

          IconButton {
            size: Theme.fs(38); glyphSize: Theme.fs(20)
            glyph: MediaState.shuffleGlyph
            active: MediaState.shuffle
            enabled: MediaState.shuffleSupported
            onClicked: MediaState.toggleShuffle()
          }
          IconButton {
            size: Theme.fs(38); glyphSize: Theme.fs(20)
            glyph: MediaState.glyphPrevious
            enabled: MediaState.canPrevious
            onClicked: MediaState.previous()
          }
          IconButton {
            size: Theme.fs(52); glyphSize: Theme.fs(28)
            glyph: MediaState.playGlyph
            enabled: MediaState.canTogglePlaying
            onClicked: MediaState.togglePlaying()
          }
          IconButton {
            size: Theme.fs(38); glyphSize: Theme.fs(20)
            glyph: MediaState.glyphNext
            enabled: MediaState.canNext
            onClicked: MediaState.next()
          }
          IconButton {
            size: Theme.fs(38); glyphSize: Theme.fs(20)
            glyph: MediaState.loopGlyph
            active: MediaState.loopActive
            enabled: MediaState.loopSupported
            onClicked: MediaState.cycleLoop()
          }
        }

        Item {
          width: parent.width
          height: Theme.fs(18)
          visible: MediaState.volumeSupported

          Text {
            id: volGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: MediaState.glyphVolume
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(13)
            color: Theme.textDim
          }
          VolumeSlider {
            anchors.left: volGlyph.right
            anchors.leftMargin: Theme.gapS
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            value: MediaState.volume
            onMoved: fraction => MediaState.setVolume(fraction)
          }
        }

        // Player selector, reusing MediaState's pin logic so the bar and the
        // dashboard never disagree about the active player.
        Rectangle {
          width: parent.width
          height: Theme.fs(26)
          radius: Theme.radiusS
          color: Theme.surface

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.gapS
            anchors.right: parent.right
            anchors.rightMargin: Theme.gapS
            anchors.verticalCenter: parent.verticalCenter
            text: MediaState.sourceLabel
                  + (MediaState.pinnedDbusName !== "" ? " (pinned)" : "")  + "  ▾"
            color: Theme.text
            font.pixelSize: Theme.fs(11)
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            onClicked: playerList.visible = !playerList.visible
          }

          Column {
            id: playerList
            visible: false
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.top
            anchors.bottomMargin: Theme.gapXS
            spacing: 2

            Repeater {
              model: MediaState.players

              Rectangle {
                required property var modelData
                readonly property bool isActive: MediaState.active === modelData
                width: playerList.width
                height: Theme.fs(24)
                radius: Theme.radiusS
                color: isActive ? Theme.accent : Theme.bgDeep

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Theme.gapS
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.identity
                  color: parent.isActive ? Theme.bgDeep : Theme.text
                  font.pixelSize: Theme.fs(11)
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

    // --- lyrics ---
    Card {
      title: "LYRICS"
      radius: Theme.radiusXL
      implicitWidth: Theme.lyricsW
      implicitHeight: root.implicitHeight

      LyricsView {
        width: Theme.lyricsW - Theme.gapL * 2
        height: root.implicitHeight - Theme.gapL * 2 - Theme.fs(22)
      }
    }
  }
}
