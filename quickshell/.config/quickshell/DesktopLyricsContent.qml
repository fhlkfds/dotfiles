import Quickshell
import QtQuick

// The current synced lyric line, large, with the next one dimmed under it.
// Reads `lyrics`, `playing` and `covered` so the smoke can hand it stand-ins;
// the window only binds `shown` and `clickMask`, which the smoke checks here
// because the offscreen platform cannot create a layer-shell window.
Item {
  id: root

  property var lyrics: LyricsState
  property bool playing: MediaState.isPlaying
  property bool covered: false
  // Long lines wrap past this width instead of running off a narrow output.
  property real maxTextWidth: Theme.fs(900)

  readonly property bool synced: lyrics.status === "synced" && lyrics.lines.length > 0
  readonly property string activeText: synced && lyrics.activeIndex >= 0
    ? lyrics.lines[lyrics.activeIndex].text : ""
  readonly property string nextText: synced && lyrics.activeIndex + 1 < lyrics.lines.length
    ? lyrics.lines[lyrics.activeIndex + 1].text : ""
  readonly property bool shown: synced && playing && !covered
  // Empty input region: every click falls through to the desktop.
  readonly property Region clickMask: Region {}

  implicitWidth: column.implicitWidth + Theme.fs(64)
  implicitHeight: column.implicitHeight + Theme.fs(40)

  Rectangle {
    anchors.fill: parent
    radius: Theme.fs(24)
    color: Theme.withAlpha(Theme.accent, 0.18)
  }

  Column {
    id: column
    anchors.centerIn: parent
    spacing: Theme.fs(10)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(implicitWidth, root.maxTextWidth)
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: root.activeText
      visible: text !== ""
      color: Theme.text
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(44)
      font.bold: true
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(implicitWidth, root.maxTextWidth)
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: root.nextText
      visible: text !== ""
      color: Theme.textDim
      font.family: Theme.uiFamily
      font.pixelSize: Theme.fs(24)
    }
  }
}
