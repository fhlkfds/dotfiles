import QtQuick

// Battery readout for a Bluetooth device: the percentage plus a thin bar.
//
// The bar is here because a bare number does not read at a glance, and a
// filling battery glyph would compete with the device-class glyph the row
// already leads with. Renders nothing when the level is unknown (-1), which
// is most non-audio devices.
Row {
  id: root
  property int level: -1
  property color barColor: Theme.accent
  property int barWidth: Theme.fs(34)
  property int textSize: Theme.fs(10)

  visible: root.level >= 0
  spacing: Theme.gapXS

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: root.level + "%"
    color: Theme.textDim
    font.pixelSize: root.textSize
    font.bold: true
  }

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: root.barWidth
    height: Theme.fs(3)
    radius: height / 2
    color: Theme.surface

    Rectangle {
      width: parent.width * Math.max(0, Math.min(100, root.level)) / 100
      height: parent.height
      radius: parent.radius
      color: root.level <= 15 ? Theme.error
           : root.level <= 30 ? Theme.warning : root.barColor

      Behavior on width {
        NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
      }
    }
  }
}
