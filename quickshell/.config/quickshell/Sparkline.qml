import QtQuick

// Line graph of recent samples, oldest on the left, with a faint fill under
// each line. Repaints only when a series changes -- once a second while the
// dashboard polls, never while it is closed.
Canvas {
  id: root
  // [{ values: [...], color: ... }]; drawn in order, so put the main series last.
  property var series: []
  // Fixed ceiling, or 0 to scale to the largest sample on screen.
  property real maxValue: 1
  // Slots across the width; fewer samples are right-aligned so the graph
  // fills in from the right like a scrolling chart.
  property int slots: 60
  property bool fill: true
  property real lineWidth: Theme.fs(1.5)

  onSeriesChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    const ctx = getContext("2d")
    ctx.reset()
    var top = root.maxValue
    if (top <= 0) {
      for (var s = 0; s < root.series.length; s++)
        for (var k = 0; k < root.series[s].values.length; k++)
          top = Math.max(top, root.series[s].values[k])
      top = top > 0 ? top * 1.15 : 1
    }
    const step = width / Math.max(1, root.slots - 1)
    const pad = root.lineWidth

    for (var i = 0; i < root.series.length; i++) {
      const vals = root.series[i].values
      if (vals.length < 2)
        continue
      const x0 = width - (vals.length - 1) * step
      ctx.beginPath()
      for (var j = 0; j < vals.length; j++) {
        const x = x0 + j * step
        const y = height - pad - Math.min(1, vals[j] / top) * (height - pad * 2)
        if (j === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      const c = root.series[i].color
      ctx.strokeStyle = c
      ctx.lineWidth = root.lineWidth
      ctx.lineJoin = "round"
      ctx.stroke()
      if (root.fill) {
        ctx.lineTo(width, height)
        ctx.lineTo(x0, height)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.14)
        ctx.fill()
      }
    }
  }
}
