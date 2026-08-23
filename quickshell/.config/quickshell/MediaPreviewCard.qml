import QtQuick

// Compact now-playing card for the Dashboard page. Drives the same MediaState
// singleton as the bar widget and the Media page -- no second MPRIS backend.
Card {
  id: root
  implicitWidth: Theme.mediaPreviewW
  implicitHeight: Theme.dateCardH
  radius: Theme.radiusXL
  padding: Theme.gapM

  Text {
    anchors.centerIn: parent
    visible: !MediaState.hasTrack
    text: "Nothing playing"
    color: Theme.textMuted
    font.pixelSize: Theme.fs(11)
  }

  Column {
    anchors.fill: parent
    anchors.margins: Theme.gapM
    spacing: Theme.gapS
    visible: MediaState.hasTrack

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Theme.fs(100)
      height: Theme.fs(100)
      radius: Theme.radiusM
      color: Theme.bgDeep
      clip: true

      Text {
        anchors.centerIn: parent
        visible: art.status !== Image.Ready
        text: MediaState.glyphMusic
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(30)
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

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: MediaState.trackTitle
      color: Theme.text
      font.bold: true
      font.pixelSize: Theme.fs(13)
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: MediaState.trackArtist
      color: Theme.textDim
      font.pixelSize: Theme.fs(11)
      elide: Text.ElideRight
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Theme.gapXS

      IconButton {
        size: Theme.fs(28); glyphSize: Theme.fs(14)
        glyph: MediaState.glyphPrevious
        enabled: MediaState.canPrevious
        onClicked: MediaState.previous()
      }
      IconButton {
        size: Theme.fs(28); glyphSize: Theme.fs(14)
        glyph: MediaState.playGlyph
        enabled: MediaState.canTogglePlaying
        onClicked: MediaState.togglePlaying()
      }
      IconButton {
        size: Theme.fs(28); glyphSize: Theme.fs(14)
        glyph: MediaState.glyphNext
        enabled: MediaState.canNext
        onClicked: MediaState.next()
      }
    }
  }
}
