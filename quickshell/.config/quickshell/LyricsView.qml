import QtQuick

// Lyrics column. The active line is derived from playback position, so seeking
// and resuming resynchronise with no extra logic.
//
// Scrolling is deliberately instant rather than eased -- smooth lyric scrolling
// was not among the requested animations.
Item {
  id: root

  // Non-interactive: the list must not be draggable out of sync with playback.
  ListView {
    id: list
    anchors.fill: parent
    visible: LyricsState.status === "synced"
    clip: true
    interactive: false
    spacing: Theme.fs(6)
    currentIndex: LyricsState.activeIndex
    // Padding so the first and last lines can still reach the centre.
    topMargin: height / 2
    bottomMargin: height / 2

    model: LyricsState.status === "synced" ? LyricsState.lines : []

    delegate: Text {
      required property var modelData
      required property int index
      width: list.width
      wrapMode: Text.WordWrap
      text: modelData.text
      horizontalAlignment: Text.AlignLeft

      readonly property int distance: Math.abs(index - LyricsState.activeIndex)
      readonly property bool isActive: index === LyricsState.activeIndex

      color: isActive ? Theme.text
           : (distance === 1 ? Theme.textDim : Theme.textMuted)
      font.pixelSize: Theme.fs(13)
      font.bold: isActive
    }

    onCurrentIndexChanged: {
      if (currentIndex >= 0)
        list.positionViewAtIndex(currentIndex, ListView.Center)
    }
  }

  // Unsynced lyrics: readable, but no highlight and no auto-scroll to fake it.
  Flickable {
    anchors.fill: parent
    visible: LyricsState.status === "plain"
    clip: true
    contentWidth: width
    contentHeight: plain.implicitHeight
    Text {
      id: plain
      width: parent.width
      wrapMode: Text.WordWrap
      text: LyricsState.plainText
      color: Theme.textDim
      font.pixelSize: Theme.fs(13)
    }
  }

  Text {
    anchors.centerIn: parent
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    visible: LyricsState.status !== "synced" && LyricsState.status !== "plain"
    color: LyricsState.status === "error" ? Theme.error : Theme.textMuted
    font.pixelSize: Theme.fs(11)
    text: {
      switch (LyricsState.status) {
      case "loading": return "Loading lyrics…"
      case "notfound": return "No lyrics found"
      case "error": return "Lyrics unavailable"
      default: return "—"
      }
    }
  }
}
