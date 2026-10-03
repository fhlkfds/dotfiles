import QtQuick
import QtQuick.Effects

// Dashboard media page: the active MPRIS player (MediaState, the same choice
// the bar's media module makes) over its own blurred cover, with a radial
// spectrum around the art, then synced lyrics underneath.
Item {
  id: root
  property bool live: false

  // MultiEffect draws nothing on the software renderer; there the art is
  // square and unblurred instead of missing (same rule as the desktop card).
  readonly property bool effects: GraphicsInfo.api !== GraphicsInfo.Software
  // Constant while off screen, so the radial bars stop re-evaluating.
  readonly property var levels: live && MediaState.isPlaying && CavaState.available ? CavaState.levels : []

  readonly property int heroH: Theme.fs(256)
  readonly property int artSize: Theme.fs(150)
  readonly property int spectrumBars: 48

  DashCard {
    id: hero
    width: parent.width
    height: root.heroH
    clip: true
    padding: 0

    // --- blurred cover backdrop ---
    Image {
      id: backdrop
      anchors.fill: parent
      source: MediaState.trackArtUrl
      sourceSize.width: Theme.fs(256)
      sourceSize.height: Theme.fs(256)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      visible: false
    }
    MultiEffect {
      anchors.fill: parent
      source: backdrop
      visible: root.effects && MediaState.hasTrack && backdrop.status === Image.Ready
      blurEnabled: true
      blur: 1
      blurMax: 64
      autoPaddingEnabled: false
      opacity: 0.35
    }

    Text {
      anchors.centerIn: parent
      visible: !MediaState.hasTrack
      text: MediaState.glyphMusic + "  Nothing playing"
      color: Theme.textMuted
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(14)
    }

    Item {
      anchors.fill: parent
      anchors.margins: Theme.gapL
      visible: MediaState.hasTrack

      // --- art + radial spectrum ---
      Item {
        id: disc
        width: parent.height
        height: parent.height
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
          model: root.spectrumBars
          Item {
            required property int index
            anchors.fill: parent
            rotation: index * 360 / root.spectrumBars
            // Mirrored, so the low end sits at the top and the ring is
            // symmetric left to right.
            readonly property real level: {
              const half = root.spectrumBars / 2
              const i = index < half ? index : root.spectrumBars - 1 - index
              return root.levels[Math.floor(i * CavaState.barCount / half)] || 0
            }
            Rectangle {
              x: (parent.width - width) / 2
              width: Theme.fs(3)
              height: Theme.fs(4) + parent.level * Theme.fs(22)
              y: parent.height / 2 - root.artSize / 2 - Theme.fs(8) - height
              radius: width / 2
              color: Theme.accent
              opacity: 0.85
            }
          }
        }

        Rectangle {
          anchors.centerIn: parent
          width: root.artSize
          height: width
          radius: root.effects ? width / 2 : Theme.radiusCell
          color: Theme.bgDeep
          Text {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            text: MediaState.glyphMusic
            color: Theme.textFaint
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(48)
          }
        }
        Image {
          id: art
          anchors.centerIn: parent
          width: root.artSize
          height: width
          source: MediaState.trackArtUrl
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          visible: !root.effects && status === Image.Ready
        }
        Rectangle {
          id: artMask
          anchors.fill: art
          radius: width / 2
          visible: false
          layer.enabled: true
        }
        MultiEffect {
          anchors.fill: art
          source: art
          maskEnabled: true
          maskSource: artMask
          visible: root.effects && art.status === Image.Ready
        }
      }

      // --- details + controls ---
      Item {
        anchors.left: disc.right
        anchors.leftMargin: Theme.gapL
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Text {
          id: source
          text: MediaState.sourceGlyph + "  " + MediaState.sourceLabel
          color: Theme.textDim
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(12)
          font.bold: true
        }
        IconButton {
          anchors.right: parent.right
          anchors.verticalCenter: source.verticalCenter
          visible: MediaState.canRaise
          bordered: false
          size: Theme.fs(26)
          glyphSize: Theme.fs(14)
          glyph: MediaState.glyphOpen
          onClicked: {
            MediaState.raisePlayer()
            DashboardState.panelVisible = false
          }
        }

        Column {
          anchors.top: source.bottom
          anchors.topMargin: Theme.gapM
          width: parent.width
          spacing: Theme.fs(2)
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: MediaState.trackTitle
            color: Theme.text
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(24)
            font.bold: true
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: MediaState.trackArtist
            color: Theme.textDim
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(15)
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            visible: text !== ""
            text: MediaState.trackAlbum
            color: Theme.accent
            font.family: Theme.glyphFamily
            font.pixelSize: Theme.fs(13)
          }
        }

        Column {
          anchors.bottom: parent.bottom
          width: parent.width
          spacing: Theme.gapM

          Item {
            width: parent.width
            height: Theme.fs(22)
            Text {
              id: elapsed
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: MediaState.formatTime(MediaState.effectivePosition)
              color: Theme.textMuted
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(11)
            }
            Text {
              id: total
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: MediaState.formatTime(MediaState.length)
              color: Theme.textMuted
              font.family: Theme.glyphFamily
              font.pixelSize: Theme.fs(11)
            }
            WaveProgress {
              id: wave
              anchors.left: elapsed.right
              anchors.right: total.left
              anchors.leftMargin: Theme.gapM
              anchors.rightMargin: Theme.gapM
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              value: MediaState.progress
              seekable: MediaState.canSeek
              animating: root.live && MediaState.isPlaying
              onMoved: fraction => MediaState.seekToFraction(fraction)
            }
            Binding { target: MediaState; property: "dragging"; value: wave.dragging; when: wave.dragging }
          }

          Item {
            width: parent.width
            height: Theme.fs(48)

            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.gapXS
              IconButton {
                anchors.verticalCenter: parent.verticalCenter
                bordered: false; size: Theme.fs(34); glyphSize: Theme.fs(16)
                glyph: MediaState.shuffleGlyph; active: MediaState.shuffle
                enabled: MediaState.shuffleSupported
                onClicked: MediaState.toggleShuffle()
              }
              IconButton {
                anchors.verticalCenter: parent.verticalCenter
                bordered: false; size: Theme.fs(34); glyphSize: Theme.fs(18)
                glyph: MediaState.glyphPrevious; enabled: MediaState.canPrevious
                onClicked: MediaState.previous()
              }
              Rectangle {
                width: Theme.fs(48)
                height: width
                radius: width / 2
                color: Theme.accent
                opacity: MediaState.canTogglePlaying ? 1 : Theme.opacityDisabled
                Text {
                  anchors.centerIn: parent
                  text: MediaState.playGlyph
                  color: Theme.onAccent
                  font.family: Theme.glyphFamily
                  font.pixelSize: Theme.fs(22)
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: MediaState.togglePlaying()
                }
              }
              IconButton {
                anchors.verticalCenter: parent.verticalCenter
                bordered: false; size: Theme.fs(34); glyphSize: Theme.fs(18)
                glyph: MediaState.glyphNext; enabled: MediaState.canNext
                onClicked: MediaState.next()
              }
              IconButton {
                anchors.verticalCenter: parent.verticalCenter
                bordered: false; size: Theme.fs(34); glyphSize: Theme.fs(16)
                glyph: MediaState.loopGlyph; active: MediaState.loopActive
                enabled: MediaState.loopSupported
                onClicked: MediaState.cycleLoop()
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: MediaState.volumeSupported
              spacing: Theme.gapS
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: MediaState.glyphVolume
                color: Theme.textDim
                font.family: Theme.glyphFamily
                font.pixelSize: Theme.fs(15)
              }
              VolumeSlider {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fs(90)
                value: MediaState.volume
                trackColor: Theme.withAlpha(Theme.foreground, 0.15)
                onMoved: fraction => MediaState.setVolume(fraction)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fs(34)
                horizontalAlignment: Text.AlignRight
                text: Math.round(MediaState.volume * 100) + "%"
                color: Theme.textDim
                font.family: Theme.glyphFamily
                font.pixelSize: Theme.fs(11)
              }
            }
          }
        }
      }
    }
  }

  DashCard {
    anchors.top: hero.bottom
    anchors.topMargin: Theme.gapM
    anchors.bottom: parent.bottom
    width: parent.width
    glyph: String.fromCodePoint(0xf0387) // md-music_note
    title: "Lyrics"

    trailing: Text {
      text: MediaState.hasTrack ? MediaState.trackTitle : ""
      width: Math.min(implicitWidth, Theme.fs(360))
      elide: Text.ElideRight
      color: Theme.textMuted
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(11)
    }

    LyricsView {
      anchors.fill: parent
      visible: MediaState.hasTrack && LyricsState.status !== "idle"
    }
    Text {
      anchors.centerIn: parent
      visible: !MediaState.hasTrack || LyricsState.status === "idle"
      text: "No lyrics"
      color: Theme.textMuted
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(12)
    }
  }
}
