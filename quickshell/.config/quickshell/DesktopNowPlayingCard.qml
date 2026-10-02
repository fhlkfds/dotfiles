import QtQuick
import QtQuick.Effects

// Spotify now-playing card drawn on the desktop: a spinning record carrying the
// album art, the title and artist, transport controls, and elapsed time.
//
// Reads everything through `media` so the smoke harness can hand it a stand-in
// with the same shape as SpotifyState. Deliberately has no queue, sleep timer
// or volume: Spotify does not expose its queue over MPRIS and ignores MPRIS
// volume on Linux, and the bar already owns volume.
Item {
  id: root

  property var media: SpotifyState
  // The window turns this off while the workspace has windows over the card,
  // so a hidden record does not keep the compositor drawing frames.
  property bool spinAllowed: true

  readonly property int discSize: Theme.fs(132)
  readonly property bool spinning: media.isPlaying && spinAllowed && visible
  readonly property string timeText:
    MediaState.formatTime(media.position) + " / " + MediaState.formatTime(media.length)

  implicitWidth: discSize + Theme.fs(22) + info.implicitWidth
  implicitHeight: discSize

  // --- record ----------------------------------------------------------------

  Item {
    id: record
    width: root.discSize
    height: root.discSize
    anchors.verticalCenter: parent.verticalCenter

    Item {
      id: disc
      anchors.fill: parent

      Image {
        id: art
        anchors.fill: parent
        source: root.media.trackArtUrl
        sourceSize.width: root.discSize * 2
        sourceSize.height: root.discSize * 2
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        visible: false
      }

      Rectangle {
        id: discMask
        anchors.fill: parent
        radius: width / 2
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: parent
        source: art
        maskEnabled: true
        maskSource: discMask
        visible: art.status === Image.Ready
      }

      // Placeholder until the art arrives, or when Spotify gives none.
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.bgDeep
        visible: art.status !== Image.Ready

        Text {
          anchors.centerIn: parent
          text: MediaState.glyphSpotify
          color: Theme.textMuted
          font.family: Theme.glyphFamily
          font.pixelSize: Theme.fs(40)
        }
      }

      // Grooves: faint concentric rings are enough to read as vinyl.
      Repeater {
        model: 4
        Rectangle {
          required property int index
          anchors.centerIn: parent
          width: disc.width * (0.9 - index * 0.14)
          height: width
          radius: width / 2
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(0, 0, 0, 0.22)
        }
      }

      // Spindle hole.
      Rectangle {
        anchors.centerIn: parent
        width: Theme.fs(14)
        height: width
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.75)
        border.width: Theme.fs(3)
        border.color: Qt.rgba(1, 1, 1, 0.55)
      }

      // Pauses in place rather than snapping back to 0 degrees.
      NumberAnimation on rotation {
        from: 0
        to: 360
        duration: 9000
        loops: Animation.Infinite
        running: root.visible
        paused: running && !root.spinning
      }
    }

    // Glass rim, outside the rotating item so its highlight stays still.
    Rectangle {
      anchors.fill: parent
      anchors.margins: -Theme.fs(4)
      radius: width / 2
      color: "transparent"
      border.width: Theme.fs(3)
      border.color: Qt.rgba(1, 1, 1, 0.35)
    }
  }

  // --- text and controls -----------------------------------------------------

  Column {
    id: info
    anchors.left: record.right
    anchors.leftMargin: Theme.fs(22)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.fs(6)
    width: Math.max(Theme.fs(420), controls.implicitWidth)

    // Text sits straight on the wallpaper like the clock, so a soft shadow is
    // what keeps it readable on a bright image.
    layer.enabled: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: Theme.shadowColor
      shadowBlur: 0.8
      shadowOpacity: 0.85
      shadowVerticalOffset: Theme.fs(1)
    }

    Text {
      id: title
      width: parent.width
      text: root.media.trackTitle.toUpperCase()
      color: Theme.text
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(26)
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      id: artist
      width: parent.width
      text: root.media.trackArtist
      color: Theme.textDim
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(16)
      font.italic: true
      elide: Text.ElideRight
    }

    Item { width: 1; height: Theme.fs(4) }

    Row {
      id: controls
      spacing: Theme.fs(14)

      CardButton {
        id: previousButton
        anchors.verticalCenter: parent.verticalCenter
        glyph: MediaState.glyphPrevious
        enabled: root.media.canPrevious
        onClicked: root.media.previous()
      }

      CardButton {
        id: playButton
        anchors.verticalCenter: parent.verticalCenter
        filled: true
        size: Theme.fs(52)
        glyphSize: Theme.fs(24)
        glyph: root.media.isPlaying
          ? String.fromCodePoint(0xf03e4)  // md-pause
          : String.fromCodePoint(0xf040a)  // md-play
        enabled: root.media.canTogglePlaying
        onClicked: root.media.togglePlaying()
      }

      CardButton {
        id: nextButton
        anchors.verticalCenter: parent.verticalCenter
        glyph: MediaState.glyphNext
        enabled: root.media.canNext
        onClicked: root.media.next()
      }

      Text {
        id: time
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: Theme.fs(8)
        text: root.timeText
        color: Theme.textDim
        font.family: Theme.uiFamily
        font.pixelSize: Theme.fs(14)
        font.features: { "tnum": 1 }
      }
    }

    Rectangle {
      width: parent.width
      height: Theme.fs(3)
      radius: height / 2
      color: Qt.rgba(1, 1, 1, 0.18)
      visible: root.media.length > 0

      Rectangle {
        width: parent.width * root.media.progress
        height: parent.height
        radius: parent.radius
        color: Theme.accent
      }
    }
  }

  // Round, frameless transport button; `filled` is the big play/pause disc.
  component CardButton: Item {
    id: button
    property string glyph: ""
    property bool filled: false
    property int size: Theme.fs(36)
    property int glyphSize: Theme.fs(22)
    signal clicked()

    width: size
    height: size
    opacity: enabled ? 1 : Theme.opacityDisabled

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: button.filled
        ? Theme.text
        : (hover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent")
      scale: tap.pressed ? 0.92 : 1
      Behavior on scale { NumberAnimation { duration: 90 } }
    }

    Text {
      anchors.centerIn: parent
      text: button.glyph
      color: button.filled ? Theme.bgDeep : Theme.text
      font.family: Theme.glyphFamily
      font.pixelSize: button.glyphSize
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: button.clicked() }
  }
}
