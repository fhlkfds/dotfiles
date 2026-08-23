import QtQuick

// Small performance card: label, primary figure, progress bar, secondary line.
// `showBar` off gives a plain two-line readout (used by Network and AC power).
Card {
  id: root
  property string glyph: ""
  // Deliberately NOT Card's `title`: this card draws its own glyph + label row,
  // and setting `title` too would render the heading twice.
  property string label: ""
  property string primary: ""
  property string secondary: ""
  property real fraction: 0
  property bool showBar: true

  implicitWidth: Theme.smallCardW
  implicitHeight: Theme.smallCardH
  radius: Theme.radiusM
  padding: Theme.gapM

  Item {
    anchors.fill: parent
    anchors.margins: Theme.gapM

    Row {
      id: head
      anchors.top: parent.top
      anchors.left: parent.left
      spacing: Theme.gapXS

      Text {
        visible: root.glyph !== ""
        text: root.glyph
        font.family: Theme.glyphFamily
        font.pixelSize: Theme.fs(11)
        color: Theme.textDim
      }
      Text {
        text: root.label
        color: Theme.textDim
        font.pixelSize: Theme.fs(10)
        font.bold: true
      }
    }

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: head.bottom
      anchors.topMargin: Theme.gapS
      spacing: Theme.gapXS

      Text {
        width: parent.width
        text: root.primary
        color: Theme.text
        font.pixelSize: Theme.fs(13)
        elide: Text.ElideRight
      }

      Rectangle {
        visible: root.showBar
        width: parent.width
        height: Theme.fs(6)
        radius: height / 2
        color: Theme.bgDeep

        Rectangle {
          width: Math.max(0, Math.min(1, root.fraction)) * parent.width
          height: parent.height
          radius: height / 2
          color: Theme.accent
        }
      }

      Text {
        width: parent.width
        text: root.secondary
        color: Theme.textMuted
        font.pixelSize: Theme.fs(10)
        wrapMode: Text.WordWrap
      }
    }
  }
}
