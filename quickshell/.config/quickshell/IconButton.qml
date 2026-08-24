import QtQuick

// Square glyph button for the media controls. The config previously hand-rolled
// this markup in NetworkPanel and AudioPanel; this is the shared version.
//
// Uses the built-in Item.enabled, which already blocks the MouseArea when false.
Item {
  id: root
  property string glyph: ""
  property bool active: false
  property int size: Theme.fs(30)
  property int glyphSize: Theme.fs(15)
  signal clicked()

  implicitWidth: size
  implicitHeight: size
  opacity: enabled ? 1 : Theme.opacityDisabled

  Rectangle {
    anchors.fill: parent
    radius: Theme.radiusCell
    color: root.active ? Theme.accent : "transparent"
    border.width: Theme.borderWidth
    border.color: root.active ? Theme.accent : Theme.surface
  }

  Text {
    anchors.centerIn: parent
    text: root.glyph
    font.family: Theme.glyphFamily
    font.pixelSize: root.glyphSize
    color: root.active ? Theme.bgDeep : Theme.text
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.clicked()
  }
}
