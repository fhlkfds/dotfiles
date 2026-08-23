import QtQuick

// CPU / GPU hero card: hardware name, ring gauge, and temperature.
// Wraps the existing Gauge.qml rather than drawing a second ring.
Card {
  id: root
  property string label: ""
  property string model: ""
  property real value: 0            // 0..1
  property string valueText: ""
  property real tempF: 0
  property bool tempAvailable: false

  implicitWidth: Theme.heroCardW
  implicitHeight: Theme.heroCardH
  radius: Theme.radiusXL

  Item {
    anchors.fill: parent
    anchors.margins: Theme.gapL

    Column {
      anchors.top: parent.top
      anchors.left: parent.left
      spacing: 1

      Text {
        text: root.label
        color: Theme.textDim
        font.pixelSize: Theme.fs(10)
        font.bold: true
      }
      Text {
        width: root.width - Theme.gapL * 2
        text: root.model !== "" ? root.model : "unknown"
        color: Theme.textMuted
        font.pixelSize: Theme.fs(9)
        elide: Text.ElideRight
      }
    }

    Gauge {
      anchors.centerIn: parent
      anchors.verticalCenterOffset: Theme.gapM
      size: Theme.heroGauge
      trackColor: Theme.bgDeep
      thickness: Theme.fs(9)
      value: root.value
      text: root.valueText
      available: true
    }

    Text {
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      text: root.tempAvailable ? Math.round(root.tempF) + "°F" : "—"
      color: root.tempAvailable ? Theme.text : Theme.textMuted
      font.pixelSize: Theme.fs(13)
    }
  }
}
