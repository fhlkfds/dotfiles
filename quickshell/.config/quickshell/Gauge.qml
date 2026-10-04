import QtQuick

// Circular ring gauge. Drawn with Canvas so no extra QML module is needed, and
// repainted only when the value actually changes.
Item {
  id: root
  property real value: 0          // 0..1
  property string label: ""       // caption under the ring
  property string text: ""        // big text inside the ring
  property color ringColor: Theme.accent
  // Must differ from whatever the gauge sits on; Theme.surface is invisible
  // against a Card, which also uses Theme.surface.
  property color trackColor: Theme.surface
  property int size: Theme.fs(72)
  property int thickness: Theme.fs(7)
  property bool available: true
  // Degrees of ring drawn. Below 360 the gap is centred at the bottom, which
  // gives the open speedometer arc the dashboard's memory and disk use.
  property real sweep: 360

  implicitWidth: size
  implicitHeight: size + (label !== "" ? Theme.fs(16) : 0)

  readonly property real clamped: Math.max(0, Math.min(1, value))

  Canvas {
    id: ring
    width: root.size
    height: root.size
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top

    // Repaint on the things the drawing depends on.
    property real v: root.available ? root.clamped : 0
    property color track: root.trackColor
    property color fill: root.ringColor
    property real sweepRad: root.sweep * Math.PI / 180
    onVChanged: requestPaint()
    onTrackChanged: requestPaint()
    onFillChanged: requestPaint()
    onSweepRadChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    property int strokeWidth: root.thickness
    onStrokeWidthChanged: requestPaint()

    onPaint: {
      const ctx = getContext("2d")
      ctx.reset()
      const cx = width / 2
      const cy = height / 2
      const r = (Math.min(width, height) - root.thickness) / 2
      const start = sweepRad >= Math.PI * 2 ? -Math.PI / 2
                                            : Math.PI / 2 + (Math.PI * 2 - sweepRad) / 2

      ctx.lineWidth = root.thickness
      ctx.lineCap = "round"

      ctx.beginPath()
      ctx.strokeStyle = track
      ctx.arc(cx, cy, r, start, start + sweepRad)
      ctx.stroke()

      if (v > 0) {
        ctx.beginPath()
        ctx.strokeStyle = fill
        ctx.arc(cx, cy, r, start, start + sweepRad * v)
        ctx.stroke()
      }
    }
  }

  Text {
    anchors.centerIn: ring
    text: root.available ? root.text : "n/a"
    color: root.available ? Theme.text : Theme.textMuted
    font.pixelSize: Theme.fs(13)
    font.bold: true
  }

  Text {
    visible: root.label !== ""
    anchors.top: ring.bottom
    anchors.topMargin: Theme.fs(2)
    anchors.horizontalCenter: parent.horizontalCenter
    text: root.label
    color: Theme.textDim
    font.pixelSize: Theme.fs(10)
  }
}
