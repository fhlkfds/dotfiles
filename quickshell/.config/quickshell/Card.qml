import QtQuick

// Surface every dashboard card sits on. Replaces the ad-hoc
// `Rectangle { radius: ...; color: Theme.surface }` that was repeated across the
// tab files.
//
// Children are placed in a plain content Item, so cards are free to position
// their contents with anchors. Cards that want vertical stacking declare their
// own Column.
Rectangle {
  id: root
  default property alias cardData: body.data

  property string title: ""
  property int padding: Theme.gapL
  property bool unavailable: false
  property string unavailableText: "unavailable"

  radius: Theme.radiusL
  color: Theme.surface
  border.width: Theme.borderWidth
  border.color: Theme.hairline
  opacity: unavailable ? Theme.opacityUnavailable : 1

  Text {
    id: heading
    visible: root.title !== ""
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.leftMargin: root.padding
    anchors.topMargin: root.padding
    text: root.title
    color: Theme.textDim
    font.pixelSize: Theme.fs(10)
    font.bold: true
  }

  // Children go into a plain Item, not a Column: most cards position their
  // content with anchors, which a Column forbids. Cards that want stacking
  // declare their own Column.
  Item {
    id: body
    anchors.fill: parent
    anchors.margins: root.padding
    anchors.topMargin: root.padding + (heading.visible ? heading.height + Theme.gapS : 0)
    visible: !root.unavailable
  }

  Text {
    anchors.centerIn: parent
    visible: root.unavailable
    text: root.unavailableText
    color: Theme.textMuted
    font.pixelSize: Theme.fs(11)
  }
}
