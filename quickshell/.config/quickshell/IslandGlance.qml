import QtQuick

// One glance drawn inside the centre island in place of the clock: a glyph,
// then the title over one line of detail, both elided to maxWidth.
Item {
  id: root
  property var glance: null
  property real barScale: 1.0
  property real maxWidth: Theme.fs(420)
  function s(n) { return Theme.fs(n * root.barScale) }

  readonly property real textWidth: Math.max(0, root.maxWidth - glyph.width - row.spacing)
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.s(8)

    Text {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      text: root.glance ? root.glance.glyph : ""
      color: Theme.accent
      font.family: Theme.glyphFamily
      font.pixelSize: root.s(16)
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter

      Text {
        width: Math.min(implicitWidth, root.textWidth)
        text: root.glance ? root.glance.title : ""
        elide: Text.ElideRight
        color: Theme.text
        font.family: Theme.glyphFamily
        font.bold: true
        font.pixelSize: root.s(12)
      }

      Text {
        width: Math.min(implicitWidth, root.textWidth)
        visible: text !== ""
        text: root.glance ? root.glance.body : ""
        elide: Text.ElideRight
        color: Theme.textDim
        font.family: Theme.glyphFamily
        font.pixelSize: root.s(9)
      }
    }
  }
}
