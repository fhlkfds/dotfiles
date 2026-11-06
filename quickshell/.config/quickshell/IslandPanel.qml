import QtQuick
import Quickshell

// The expanded island: opens under the capsule while the pointer rests on a
// glance, and closes a moment after it leaves both. No keyboard focus, so a
// glance never steals typing.
PopupWindow {
  id: panel
  required property Item anchorItem
  required property string ownerScreen

  visible: IslandState.expandedScreen === panel.ownerScreen
  color: "transparent"

  anchor.item: anchorItem
  anchor.edges: Edges.Bottom
  anchor.gravity: Edges.Bottom
  anchor.margins.top: Theme.gapS

  implicitWidth: Theme.fs(360)
  implicitHeight: body.implicitHeight + Theme.gapL * 2

  Rectangle {
    anchors.fill: parent
    radius: Theme.gapL
    color: Theme.bgDeep

    HoverHandler {
      onHoveredChanged: IslandState.hover(panel.ownerScreen, hovered)
    }

    IslandPanelContent {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.gapL
      media: IslandState.media
      lyricLine: LyricsState.activeIndex >= 0
                 ? LyricsState.lines[LyricsState.activeIndex].text : ""
      onMediaClicked: {
        IslandState.collapse()
        MediaState.togglePanel(panel.ownerScreen)
      }
    }
  }
}
