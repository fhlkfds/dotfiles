import QtQuick

// Card for the clock dashboard: a raised surface with an optional glyph +
// title header. Children go into `body`, below the header. `trailing` holds
// anything right-aligned in the header row (a refresh button, a chip).
Rectangle {
  id: root
  default property alias content: body.data
  property alias trailing: trailingSlot.data
  property string glyph: ""
  property string title: ""
  property int padding: Theme.gapM
  readonly property bool hasHeader: title !== "" || glyph !== ""

  radius: Theme.radiusS
  color: Theme.mixColor(Theme.bg, Theme.surfaceColor, 0.55)
  border.width: Theme.borderWidth
  border.color: Theme.hairline

  Row {
    id: header
    visible: root.hasHeader
    x: root.padding
    y: root.padding
    spacing: Theme.gapS

    Text {
      visible: root.glyph !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.glyph
      color: Theme.accent
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(14)
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.title
      color: Theme.text
      font.family: Theme.glyphFamily
      font.pixelSize: Theme.fs(13)
      font.bold: true
    }
  }

  Item {
    id: trailingSlot
    anchors.right: parent.right
    anchors.rightMargin: root.padding
    y: root.padding
    width: childrenRect.width
    height: header.height
  }

  Item {
    id: body
    anchors.fill: parent
    anchors.margins: root.padding
    anchors.topMargin: root.padding + (root.hasHeader ? header.height + Theme.gapS : 0)
  }
}
