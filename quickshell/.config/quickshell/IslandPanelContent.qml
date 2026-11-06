import QtQuick

// What the expanded island lists: now playing with the current lyric line.
// Takes plain objects so IslandSmoke can load it with fakes.
Column {
  id: root
  property var media: null
  property string lyricLine: ""
  signal mediaClicked()

  readonly property bool hasTrack: !!(root.media && root.media.hasTrack)
  spacing: Theme.gapM

  Item {
    objectName: "islandNowPlaying"
    width: root.width
    height: nowPlaying.implicitHeight
    visible: root.hasTrack

    Column {
      id: nowPlaying
      width: parent.width

      Text {
        width: parent.width
        text: root.hasTrack ? root.media.trackTitle : ""
        elide: Text.ElideRight
        color: Theme.text
        font.family: Theme.glyphFamily
        font.bold: true
        font.pixelSize: Theme.fs(13)
      }
      Text {
        width: parent.width
        text: root.hasTrack ? root.media.trackArtist : ""
        elide: Text.ElideRight
        color: Theme.textDim
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(11)
      }
      Text {
        objectName: "islandLyric"
        width: parent.width
        visible: text !== ""
        text: root.lyricLine
        elide: Text.ElideRight
        color: Theme.accent
        font.family: Theme.glyphFamily
        font.italic: true
        font.pixelSize: Theme.fs(11)
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.mediaClicked()
    }
  }
}
